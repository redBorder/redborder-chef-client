Ohai.plugin(:Redborder) do
  provides 'redborder'

  collect_data do
    redborder Mash.new
    redborder[:rpms] = Mash.new
    redborder[:is_sensor] = false
    redborder[:is_manager] = false
    redborder[:is_proxy] = false

    rpms = shell_out('rpm -qa | grep redborder-').stdout

    rpms.each_line do |line|
      r = /redborder-(manager|repo|common|malware|proxy|ips)-(.*)\.(noarch)/
      m = r.match(line.chomp)
      next unless m

      redborder[:rpms][m[1]] = m[2].gsub(".el9.rb", "")
      redborder[:is_manager] = true  if m[1] == "manager"
      redborder[:is_sensor] = true if m[1] == "ips"
      redborder[:is_proxy] = true if m[1] == "proxy"
    end

    if redborder[:is_sensor]
      rpms = shell_out('rpm -qa | grep -E "(snort-|barnyard2-)"').stdout
      rpms.each_line do |line|
        r = /(snort|barnyard2)-(.*)\.(x86_64)/
        m = r.match(line.chomp)
        next unless m

        if m[1] == "snort"
          redborder[:snort] = Mash.new
          redborder[:snort][:version] =  m[2].gsub(".el9", "")
        elsif m[1] == "barnyard2"
          redborder[:barnyard2] = Mash.new
          redborder[:barnyard2][:version] =  m[2].gsub(".el9", "")
        end
      end
    end

    # get webui version
    if redborder[:is_manager]
      rpms = shell_out('rpm -qa | grep -E "(redborder-webui-)"').stdout
      rpms.each_line do |line|
        r = /(redborder-webui)-(.*)\.(noarch)/
        m = r.match(line.chomp)
        next unless m

        if m[1] == "redborder-webui"
          redborder[:webui] = Mash.new
          redborder[:webui][:version] =  m[2].gsub(".el9.rb", "")
        end
      end
    end

    # get repo version
    rpms = shell_out('rpm -qa | grep -E "(redborder-repo-)"').stdout
    rpms.each_line do |line|
      r = /(redborder-repo)-(.*)\.(noarch)/
      m = r.match(line.chomp)
      next unless m

      if m[1] == "redborder-repo"
        redborder[:repo] = Mash.new
        redborder[:repo][:version] =  m[2].gsub(".el9.rb", "")
      end
    end

    redborder[:dmidecode] = Mash.new
    redborder[:dmidecode][:manufacturer] = shell_out('dmidecode -t 1 | grep "Manufacturer:" | sed "s/.*Manufacturer: //"').stdout.chomp
    redborder[:dmidecode][:product_name] = shell_out('dmidecode -t 1 | grep "Product Name:" | sed "s/.*Product Name: //"').stdout.chomp
    redborder[:dmidecode][:serial_number] = shell_out('dmidecode -t 1 | grep "Serial Number:" | sed "s/.*Serial Number: //"').stdout.chomp
    redborder[:dmidecode][:uui] = shell_out('dmidecode -t 1 | grep "UUID: " | sed "s/.*UUID: //"').stdout.chomp
    redborder[:iscloud] = (redborder[:dmidecode][:manufacturer].to_s.downcase == "xen" || redborder[:dmidecode][:manufacturer].to_s.downcase.include?("openstack") || redborder[:dmidecode][:product_name].to_s.downcase.include?("openstack"))

    if redborder[:dmidecode][:manufacturer] == "Supermicro"
      redborder[:dmidecode][:version] = shell_out('dmidecode -t 1 | grep "Version:" | sed "s/.*Version: //"').stdout.chomp
    end

    # set manager_registration_ip
    if redborder[:is_sensor] || redborder[:is_proxy]
      conf ||= YAML.load_file('/etc/redborder/rb_init_conf.yml')
      redborder[:manager_registration_ip] = conf['cloud_address'] if conf && conf['cloud_address']
      redborder[:manager_registration_ip] = conf['webui_host'] if redborder[:is_sensor] && conf && conf['webui_host']
    end

    if redborder[:is_manager]
      redborder[:leader_configuring] = ::File.exist?('/var/lock/leader-configuring.lock')

      redborder[:cluster] = Mash.new
      redborder[:cluster][:general] = Mash.new
      redborder[:cluster][:services] = []
      redborder[:cluster][:members] = []
      redborder[:cluster][:general][:timestamp] = Time.now.to_i

      services = ["chef-client", "consul", "zookeeper", "kafka", "webui", "rb-workers", "redborder-monitor", "druid-coordinator",
                  "druid-realtime", "druid-middlemanager", "druid-overlord", "druid-historical", "druid-broker", "opscode-erchef",
                  "postgresql", "redborder-postgresql", "nginx", "memcached", "n2klocd", "redborder-nmsp",
                  "opscode-bookshelf", "opscode-chef-mover", "opscode-rabbitmq", "http2k", "redborder-cep", "snmpd", "snmptrapd",
                  "redborder-dswatcher", "redborder-events-counter", "sfacctd", "redborder-ale", "logstash", "mongod", "minio", "redborder-ai"]
      services.each do |s|
        service_data = Mash.new
        service_data[:name] = s

        is_service_running = shell_out("systemctl is-active #{s}").stdout.chomp == "active"
        is_service_enabled = shell_out("systemctl is-enabled #{s}").stdout.chomp == "enabled"

        if is_service_running
          service_data[:status] = is_service_running
          service_data[:ok] = is_service_enabled
        else
          service_data[:status] = is_service_running
          service_data[:ok] = !is_service_enabled
        end

        redborder[:cluster][:services] << service_data
      end

      redborder[:kafka] = Mash.new
      if File.exist?("/tmp/kafka/meta.properties")
        kafka_configured_id = shell_out('grep "^broker.id=" /tmp/kafka/meta.properties | tr "=" " " | awk "{print $2}"').stdout.chomp
      else
        kafka_configured_id = ""
      end
      kafka_configured_id = "-1" if kafka_configured_id.nil? || kafka_configured_id.empty?
      redborder[:kafka]["configured_id"] = kafka_configured_id.to_i

      if File.exist?('/etc/redborder/rb_init_conf.yml')
        management_iface = File.read('/etc/redborder/rb_init_conf.yml').match(/management_interface: (\S+)/)[1]
        redborder[:management_interface] = management_iface

        sync_interface = File.read('/etc/redborder/rb_init_conf.yml').match(/sync_interface: (\S+)/)[1]
        redborder[:sync_interface] = sync_interface
      end
    else
      redborder[:ipmi] = Mash.new
      redborder[:ipmi][:lan] = Mash.new
      redborder[:ipmi][:lan][:ipaddress] = shell_out('ipmitool lan print 2>/dev/null | egrep "^IP Address [ ]+:" | sed "s/IP Address[^:]*://" | awk "{print $1}"').stdout.chomp
      redborder[:ipmi][:lan][:mask] = shell_out('ipmitool lan print 2>/dev/null | egrep "^Subnet Mask [ ]+:" | sed "s/Subnet Mask[^:]*://" | awk "{print $1}"').stdout.chomp
      redborder[:ipmi][:lan][:gateway] = shell_out('ipmitool lan print 2>/dev/null | egrep "^Default Gateway IP [ ]+:" | sed "s/Default Gateway IP[^:]*://" | awk "{print $1}"').stdout.chomp
      redborder[:ipmi][:lan][:macaddress] = shell_out('ipmitool lan print 2>/dev/null | egrep "^MAC Address [ ]+:" | sed "s/MAC Address[^:]*://" | awk "{print $1}"').stdout.chomp
      redborder[:ipmi][:sol] = Mash.new
      redborder[:ipmi][:sol][:kbps] = shell_out('ipmitool sol info 2>/dev/null | egrep "^Volatile" | awk -F ":" "{print $2}" | awk "{print $1}"').stdout.chomp
      redborder[:ipmi][:sensors] = []

      if redborder[:dmidecode][:manufacturer] == "Supermicro"
        ipmi_cmds = ["ipmitool sdr"]
      else
        ipmi_cmds = ["ipmitool sdr type Fan", "ipmitool sdr type Temperature"]
      end

      ipmi_cmds = [] if shell_out('rpm -qa | grep -q ipmitool').stdout.chomp != 0

      ipmi_cmds.each do |cmd|
        if cmd == "ipmitool sdr"
          shell_out(cmd).stdout.each_line do |line|
            split = line.split("|")
            if split.count >= 3
              sensor_data = Mash.new
              sensor_data[:sensor] = split[0].strip
              sensor_data[:value] = split[1].strip
              sensor_data[:status] = split[2].strip
              redborder[:ipmi][:sensors] << sensor_data
            end
          end
        else
          shell_out(cmd).stdout.each_line do |line|
            split = line.split("|")
            if split.count >= 5
              sensor_data = Mash.new
              sensor_data[:sensor] = split[0].strip
              sensor_data[:value] = split[4].strip
              sensor_data[:status] = split[2].strip
              redborder[:ipmi][:sensors] << sensor_data
            end
          end
        end
      end
    end

    redborder[:fqdn] = shell_out('/bin/hostname 2>/dev/null').stdout.chomp

    redborder[:uptime] = Mash.new
    match = shell_out('uptime | sed "s/.*load average: //" | tr "," " "').stdout.chomp.match(/([^ ]+)[ ]+([^ ]+)[ ]+([^ ]*)/)
    unless match.nil?
      redborder[:uptime]["1minute"] = match[1]
      redborder[:uptime]["5minute"] = match[2]
      redborder[:uptime]["15minute"] = match[3]
    end

    if redborder[:is_manager]
      redborder[:install_date] = shell_out('[ -f /etc/redborder/cluster-installed.txt ] && cat /etc/redborder/cluster-installed.txt 2>/dev/null').stdout.chomp
    else
      redborder[:install_date] = shell_out('[ -f /etc/redborder/sensor-installed.txt ] && cat /etc/redborder/sensor-installed.txt 2>/dev/null').stdout.chomp
    end

    redborder[:manager_host] = shell_out('cat /etc/chef/client.rb | grep chef_server_url | awk \'{print $2}\' | sed \'s|^.*//||\' | sed \'s|".*$||\' | awk \'{printf("%s", $1);}\'').stdout.chomp

    redborder[:has_watchdog] = File.chardev?("/dev/watchdog")

    if redborder[:is_sensor]
      redborder[:segments] = Mash.new
      bond_index = 0
      has_bypass = false

      # <get IPS model>
      models_map = {}
      models_map['ips2030'] = { 'model' => 'redborder IPS 2030', 'cpu' => 'E5-1630v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '0' }
      models_map['ips2080'] = { 'model' => 'redborder IPS 2080', 'cpu' => 'E5-1680v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '32' }
      models_map['ips2090'] = { 'model' => 'redborder IPS 2090', 'cpu' => 'E5-2699v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '64' }
      models_map['ips3040'] = { 'model' => 'redborder IPS 3040', 'cpu' => 'E5-2640v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '64' }
      models_map['ips3080'] = { 'model' => 'redborder IPS 3080', 'cpu' => 'E5-2680v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '128' }
      models_map['ips4010'] = { 'model' => 'redborder IPS 4010', 'cpu' => 'E5-2699v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '128' }

      specs = {}
      specs['cpu_model'] = shell_out('cat /proc/cpuinfo | grep -m1 "model name" | awk "{print $7 $8}"').stdout.chomp
      specs['sockets'] = shell_out('lscpu | grep Socket | awk "{print $2}"').stdout.chomp
      specs['motherboard'] = shell_out('dmidecode -t2 | grep "Product Name:" | awk "{print $3}"').stdout.chomp
      ramkb = shell_out('cat /proc/meminfo | grep MemTotal | awk "{print $2}"').stdout.to_f
      specs['ramgb'] = ramkb / 1000000

      redborder[:IPS_model] = "Commodity hardware"

      models_map.each_value do |v|
        if v['cpu'] == specs['cpu_model'] && v['sockets'] == specs['sockets'] && v['motherboard'] == specs['motherboard'] && v['minimal_ram'].to_f < specs['ramgb'].to_f
          redborder[:IPS_model] = v['model']
        end
      end
      # </get IPS model

      netDir = Dir.open('/sys/class/net/')
      netDir.each do |iface|
        next if iface == "." || iface == ".."
        next unless iface =~ /^bpbr[\d]+$|^br[\d]+$/

        has_bypass = true if iface =~ /^bpbr[\d]+$/

        redborder[:segments][iface.to_sym] = Mash.new
        redborder[:segments][iface.to_sym][:interfaces] = {}
        bridgeDir = Dir.open("/sys/class/net/#{iface.to_s}/brif/")
        counter = 0
        iface_master = ""
        bridge_speed = ""
        bridge_type = ""
        bridgeDir.each do |eth|
          next if eth == "." || eth == ".."
          next unless eth =~ /^e*/
          thash = {}
          thash[:status] = shell_out("cat /sys/class/net/#{eth.to_s}/operstate 2>/dev/null").stdout.chomp
          thash[:type] = shell_out("ethtool #{eth.to_s} 2>/dev/null | grep \"Supported ports:\" | sed \"s/Supported ports: //\" | tr '[' ' ' | tr ']' ' ' | awk \"{print $1}\"").stdout.chomp.downcase
          thash[:type] = "copper" if thash[:type] != "fibre"
          # TODO
          # thash[:bus] = shell_out("/opt/rb/bin/rb_get_bus.sh #{eth.to_s} 2>/dev/null").stdout.chomp.downcase
          thash[:driver] = shell_out("ethtool -i #{eth.to_s} | grep \"^driver:\" |awk \"{print $2}\"").stdout.chomp.downcase

          if thash[:driver] == "ixgbe"
            thash[:speed] = "10G"
          elsif thash[:driver] == "igb" || thash[:driver] == "e1000e" || thash[:driver] == "bnx2"
            thash[:speed] = "1G"
          else
            thash[:speed] = "unknown"
          end

          if bridge_speed == ""
            bridge_speed = thash[:speed]
          elsif bridge_speed != thash[:speed]
            bridge_speed = "#{bridge_speed}/#{thash[:speed]}"
          end

          if bridge_type == ""
            bridge_type = thash[:type]
          elsif bridge_type != thash[:type]
            bridge_type = "#{bridge_type}/#{thash[:type]}"
          end

          redborder[:segments][iface.to_sym][:interfaces][eth.to_sym] = thash
          if shell_out("bpctl_util #{eth} is_bypass|grep -q \"^The interface is a control interface\"; echo $?").stdout.chomp == "0"
            iface_master = eth.to_s
          end
          counter += 1
        end

        redborder[:segments][iface.to_sym][:speed] = bridge_speed
        redborder[:segments][iface.to_sym][:type] = bridge_type

        if counter > 0
          bond_index = bond_index + 1
          if ((iface =~ /^bpbr[\d]+$/) && iface_master != "")
            if shell_out("bpctl_util #{eth} is_bypass|grep -q \"^The interface is a control interface\"; echo $?").stdout.chomp == "0"
              redborder[:segments][iface.to_sym][:master] = iface_master
              redborder[:segments][iface.to_sym][:bypass] = (shell_out("bpctl_util #{iface_master} get_bypass|grep -q non-Bypass; [ $? -eq 0 ] && echo disabled || echo enabled").stdout.chomp == "enabled")
            end
          else
            redborder[:segments][iface.to_sym][:master] = "n/a"
            redborder[:segments][iface.to_sym][:bypass] = false
          end
        end

        if shell_out("/usr/lib/redborder/bin/rb_bypass.sh -b #{iface} -g &>/dev/null; echo -n $?").stdout.chomp == "1"
          redborder[:segments][iface.to_sym]["status"] = "bypass"
        else
          redborder[:segments][iface.to_sym]["status"] = "on"
        end
      end

      redborder[:has_bypass] = has_bypass

      netDir = Dir.open('/sys/class/net/')
      netDir.each do |iface|
        next if iface == "." || iface == ".."
        next unless iface =~ /^dna[02468]+$/
        dna_index = iface.match(/^dna([\d]+)$/)[1].to_i
        if dna_index % 2 == 0
          dna_bond_index = bond_index + dna_index / 2
          bypass = shell_out("bpctl_util #{iface} is_bypass|egrep -q \"The interface is a control interface|The interface is a slave interface\"; [ $? -eq 0 ] && echo 1 || echo 0").stdout.chomp == "1"
          bond_iface = bypass ? "bpbr#{dna_bond_index}" : "br#{dna_bond_index}"
          redborder[:segments][bond_iface.to_sym] = Mash.new
          redborder[:segments][bond_iface.to_sym][:interfaces] = {}

          [iface, "dna#{dna_index + 1}"].each do |eth|
            thash = {}
            thash[:status] = shell_out("cat /sys/class/net/#{eth.to_s}/operstate 2>/dev/null").stdout.chomp
            thash[:type] = shell_out("ethtool #{eth.to_s} 2>/dev/null | grep \"Supported ports:\" | sed \"s/Supported ports: //\" | tr '[' ' ' | tr ']' ' ' | awk \"{print $1}\"").stdout.chomp.downcase
            redborder[:segments][bond_iface.to_sym][:interfaces][eth.to_sym] = thash
          end

          if bypass
            redborder[:segments][bond_iface.to_sym][:master] = iface
            redborder[:segments][bond_iface.to_sym][:bypass] = (shell_out("bpctl_util #{iface} get_bypass|grep -q non-Bypass; [ $? -eq 0 ] && echo disabled || echo enabled").stdout.chomp == "enabled")
          else
            redborder[:segments][bond_iface.to_sym][:master] = "n/a"
            redborder[:segments][bond_iface.to_sym][:bypass] = false
          end
        end
      end
    end

    domain=`/bin/hostname -d 2>/dev/null`.chomp
    domain=`grep domain /etc/resolv.conf|awk '{print $2}'`.chomp if domain==""
    domain=`grep search /etc/resolv.conf|awk '{print $4}'`.chomp if domain=="" and redborder[:is_manager]
    domain=`grep search /etc/resolv.conf|awk '{print $2}'`.chomp if domain=="" and (redborder[:is_proxy] or redborder[:is_sensor])
    domain="redborder.cluster" if domain==""

    redborder[:domain]=domain

  end

end
