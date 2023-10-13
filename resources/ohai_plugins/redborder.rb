provides 'redborder'

redborder Mash.new
redborder[:rpms] = Mash.new
redborder[:is_sensor]=false
redborder[:is_manager]=false

rpms = `rpm -qa | grep redborder-`

%w(manager proxy ips).map { |m_type| redborder[("is_"+m_type).to_sym] = rpms.include?(m_type) }

rpms.each_line do |line|
  r = /redborder-([a-z]*)-(.*)\.(noarch)/
  m = r.match line.chomp
  if m.nil?
    # it could be a IPS sensor
    r = /redborder-([a-zA-Z]*)-([a-z]*)-(.*)\.(noarch)/
    m = r.match line.chomp
    if !m.nil?
      redborder[:rpms]["#{m[1]}-#{m[2]}"] = m[3]
      if (m[1]=="IPS" and m[2]=="sensor")
        redborder[:is_sensor]=true
        redborder[:snort]= Mash.new
        redborder[:snort][:version] = `snort --version 2>&1|grep Version|sed 's/.*Version //' | sed 's/ .*//'|awk '{printf("%s", $1)}'`
        redborder[:barnyard2]= Mash.new
        redborder[:barnyard2][:version] = `barnyard2 --version 2>&1|grep -i Version|sed 's/.*Version //'| sed 's/ .*//'|awk '{printf("%s", $1)}'`
      end
    end
  else
    if (m[1]=="manager" || m[1]=="repo" || m[1]=="common" || m[1]=="malware")
      redborder[:rpms][m[1]] = m[2].gsub(".el7.rb", "")
    end
    #TODO: double assignation: is_manager was already assigned
    if (m[1]=="manager")
      redborder[:is_manager]=true
    end
  end
end


redborder[:dmidecode] = Mash.new
redborder[:dmidecode][:manufacturer]  = `dmidecode -t 1| grep "Manufacturer:" | sed 's/.*Manufacturer: //'`.chomp
redborder[:dmidecode][:product_name]  = `dmidecode -t 1| grep "Product Name:" | sed 's/.*Product Name: //'`.chomp
redborder[:dmidecode][:serial_number] = `dmidecode -t 1| grep "Serial Number:" | sed 's/.*Serial Number: //'`.chomp
redborder[:dmidecode][:uui]           = `dmidecode -t 1| grep "UUID: " | sed 's/.*UUID: //'`.chomp
redborder[:iscloud]                   = (redborder["dmidecode"]["manufacturer"].to_s.downcase == "xen" or redborder["dmidecode"]["manufacturer"].to_s.downcase.include?"openstack" or redborder[:dmidecode][:product_name].to_s.downcase.include?"openstack")

`dmidecode -t 1| grep "UUID: " | sed 's/.*UUID: //'`.chomp

if redborder[:dmidecode][:manufacturer]=="Supermicro"
  redborder[:dmidecode][:version]       = `dmidecode -t 1| grep "Version:" | sed 's/.*Version: //'`.chomp
end

if redborder[:is_manager]
  redborder[:cluster] = Mash.new
  redborder[:cluster][:general]  = Mash.new
  redborder[:cluster][:services] = Array.new
  redborder[:cluster][:members]  = Array.new
  redborder[:cluster][:general][:timestamp] = Time.now.to_i

  services=["chef-client", "consul", "zookeeper", "kafka", "webui", "rb-workers", "redborder-monitor", "druid-coordinator", 
            "druid-realtime", "druid-middlemanager", "druid-overlord", "druid-historical", "druid-broker", "opscode-erchef", 
            "postgresql", "redborder-postgresql", "nginx", "memcached", "n2klocd", "redborder-nmsp",  
            "opscode-bookshelf", "opscode-chef-mover", "opscode-rabbitmq", "http2k", "redborder-cep", "snmpd", "snmptrapd", 
            "redborder-dswatcher", "redborder-events-counter", "sfacctd", "redborder-ale", "logstash", "mongod", "minio"]
  services.each_with_index do |s,i|
    redborder[:cluster][:services] << Mash.new
    redborder[:cluster][:services][i][:name] = s

    is_service_running = `systemctl is-active #{s}`.chomp == "active"
    is_service_enabled = `systemctl is-enabled #{s}`.chomp == "enabled"
    #TODO: optimize
    # I propose:
    # redborder[:cluster][:services][i][:status] =  is_service_running
    # redborder[:cluster][:services][i][:ok]     =  is_service_enabled == is_service_running
    if is_service_running
      redborder[:cluster][:services][i][:status] =  is_service_running
      redborder[:cluster][:services][i][:ok]     =  is_service_enabled
    else
      redborder[:cluster][:services][i][:status] =  is_service_running
      redborder[:cluster][:services][i][:ok]     =  !is_service_enabled
    end
  end

  redborder["kafka"] = Mash.new
  if File.exists?"/tmp/kafka/meta.properties"
    kafka_configured_id=`grep "^broker.id=" /tmp/kafka/meta.properties|tr '=' ' '|awk '{print $2}'`.chomp
  else
    kafka_configured_id=""
  end
  kafka_configured_id="-1" if kafka_configured_id.nil? or kafka_configured_id.empty?
  redborder["kafka"]["configured_id"] = kafka_configured_id.to_i

else
  redborder[:ipmi] = Mash.new
  redborder[:ipmi][:lan] = Mash.new
  redborder[:ipmi][:lan][:ipaddress]  = `ipmitool lan print 2>/dev/null|egrep "^IP Address [ ]+:"|sed 's/IP Address[^:]*://'|awk '{print $1}'`.chomp
  redborder[:ipmi][:lan][:mask]       = `ipmitool lan print 2>/dev/null|egrep "^Subnet Mask [ ]+:"|sed 's/Subnet Mask[^:]*://'|awk '{print $1}'`.chomp
  redborder[:ipmi][:lan][:gateway]    = `ipmitool lan print 2>/dev/null|egrep "^Default Gateway IP [ ]+:"|sed 's/Default Gateway IP[^:]*://'|awk '{print $1}'`.chomp
  redborder[:ipmi][:lan][:macaddress] = `ipmitool lan print 2>/dev/null|egrep "^MAC Address [ ]+:"|sed 's/MAC Address[^:]*://'|awk '{print $1}'`.chomp
  redborder[:ipmi][:sol]              = Mash.new
  redborder[:ipmi][:sol][:kbps]       = `ipmitool sol info 2>/dev/null|egrep "^Volatile"|awk -F ':' '{print $2}'|awk '{print $1}'`.chomp
  redborder[:ipmi][:sensors]          = Array.new

  if redborder[:dmidecode][:manufacturer]=="Supermicro"
    ipmi_cmds=["ipmitool sdr"]
  else
    ipmi_cmds=["ipmitool sdr type Fan", "ipmitool sdr type Temperature"]
  end

  ipmi_cmds.each do |cmd|
    if cmd=="ipmitool sdr"
      `#{cmd} 2>/dev/null`.split("\n").each do |line|
        split = line.split("|")
        if split.count>=3
          mash = Mash.new
          mash[:sensor] = split[0].strip
          mash[:value]  = split[1].strip
          mash[:status] = split[2].strip
          redborder[:ipmi][:sensors] << mash
        end
      end
    else
      `#{cmd} 2>/dev/null`.split("\n").each do |line|
        split = line.split("|")
        if split.count>=5
          mash = Mash.new
          mash[:sensor] = split[0].strip
          mash[:value]  = split[4].strip
          mash[:status] = split[2].strip
          redborder[:ipmi][:sensors] << mash
        end
      end
    end
  end
end

redborder[:fqdn]= `/bin/hostname 2>/dev/null`.chomp

redborder[:uptime] = Mash.new
match = /([^ ]+)[ ]+([^ ]+)[ ]+([^ ]*)/.match(`uptime |sed 's/.*load average: //'|tr ',' ' '`.chomp)
unless match.nil?
  redborder[:uptime]["1minute"]  = match[1]
  redborder[:uptime]["5minute"]  = match[2]
  redborder[:uptime]["15minute"] = match[3]
end


inst = `rpm -q basesystem --qf '%{installtime:date}\n'`.chomp
redborder[:install_date] = inst

redborder[:manager_host] = `[ -f /etc/chef/client.rb ] && cat /etc/chef/client.rb |grep chef_server_url|awk '{print $2}'|sed 's|^.*//||'|sed 's|".*$||'|awk '{printf("%s",$1);}'`

redborder[:has_watchdog] = File.chardev? "/dev/watchdog"

if redborder[:is_sensor]
  redborder[:segments]= Mash.new
  bond_index = 0
  has_bypass = false

  #<get IPS model>
  models_map = {}
  models_map['ips2030'] = {'model' => 'redborder IPS 2030', 'cpu' => 'E5-1630v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '0'}
  models_map['ips2080'] = {'model' => 'redborder IPS 2080', 'cpu' => 'E5-1680v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '32'}
  models_map['ips2090'] = {'model' => 'redborder IPS 2090', 'cpu' => 'E5-2699v3', 'sockets' => '1', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '64'}
  models_map['ips3040'] = {'model' => 'redborder IPS 3040', 'cpu' => 'E5-2640v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '64'}
  models_map['ips3080'] = {'model' => 'redborder IPS 3080', 'cpu' => 'E5-2680v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '128'}
  models_map['ips4010'] = {'model' => 'redborder IPS 4010', 'cpu' => 'E5-2699v3', 'sockets' => '2', 'motherboard' => 'X10SRL-F', 'minimal_ram' => '128'}

  specs = {}
  specs['cpu_model'] = `cat /proc/cpuinfo | grep -m1 "model name" | awk '{print $7 $8}'`.delete!("\n")
  specs['sockets'] = `lscpu | grep Socket | awk '{print $2}'`.delete!("\n")
  specs['motherboard'] = `dmidecode -t2 | grep "Product Name:" | awk '{print $3}'`.delete!("\n")
  ramkb = `cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
  specs['ramgb'] = ramkb.to_f / 1000000

  redborder[:IPS_model] = "Commodity hardware"

  models_map.each_value do |v|
    if v['cpu'] == specs['cpu_model'] and v['sockets'] == specs['sockets'] and v['motherboard'] == specs['motherboard'] and v['minimal_ram'].to_f < specs['ramgb'].to_f
      redborder[:IPS_model] = v['model']
    end
  end
  #</get IPS model

  netDir = Dir.open('/sys/class/net/')
  netDir.to_a.each do |iface|
    next if iface == "." or iface == ".."
    next unless iface =~ /^bpbr[\d]+$|^br[\d]+$/

    has_bypass = true if iface =~ /^bpbr[\d]+$/

    redborder[:segments][iface.to_sym]= Mash.new
    redborder[:segments][iface.to_sym][:interfaces]={}
    bridgeDir = Dir.open("/sys/class/net/#{iface.to_s}/brif/")
    counter=0
    iface_master = ""
    bridge_speed = ""
    bridge_type  = ""
    bridgeDir.to_a.each do |eth|
      next if eth == "." or eth == ".."
      next unless eth =~ /^e*/
      thash={}
      thash[:status]=`cat /sys/class/net/#{eth.to_s}/operstate 2>/dev/null`.chomp
      thash[:type]=`ethtool #{eth.to_s} 2>/dev/null | grep "Supported ports:" | sed 's/Supported ports: //' | tr '[' ' ' | tr ']' ' ' | awk '{print $1}'`.chomp.downcase
      thash[:type]="copper" if thash[:type]!="fibre"
      # TODO
      # thash[:bus]=`/opt/rb/bin/rb_get_bus.sh #{eth.to_s} 2>/dev/null`.chomp.downcase
      thash[:driver]=`ethtool -i #{eth.to_s} | grep "^driver:" |awk '{print $2}'`.chomp.downcase

      if thash[:driver]=="ixgbe"
        thash[:speed]="10G"
      elsif thash[:driver]=="igb" or thash[:driver]=="e1000e" or thash[:driver]=="bnx2"
        thash[:speed]="1G"
      else
        thash[:speed]="unknown"
      end

      if bridge_speed==""
        bridge_speed=thash[:speed]
      elsif bridge_speed!=thash[:speed]
        bridge_speed="#{bridge_speed}/#{thash[:speed]}"
      end

      if bridge_type==""
        bridge_type=thash[:type]
      elsif bridge_type!=thash[:type]
        bridge_type="#{bridge_type}/#{thash[:type]}"
      end

      redborder[:segments][iface.to_sym][:interfaces][eth.to_sym]=thash
      if `bpctl_util #{eth} is_bypass|grep -q "^The interface is a control interface"; echo $?`.chomp == "0"
        iface_master=eth.to_s
      end
      counter+=1
    end

    redborder[:segments][iface.to_sym][:speed] = bridge_speed
    redborder[:segments][iface.to_sym][:type]  = bridge_type

    if counter>0
      bond_index = bond_index+1
      if ((iface =~ /^bpbr[\d]+$/) && iface_master!="")
        if `bpctl_util #{eth} is_bypass|grep -q "^The interface is a control interface"; echo $?`.chomp == "0"
          redborder[:segments][iface.to_sym][:master] = iface_master
          redborder[:segments][iface.to_sym][:bypass] = (`bpctl_util #{iface_master} get_bypass|grep -q non-Bypass; [ $? -eq 0 ] && echo disabled || echo enabled`.chomp == "enabled")
        end
      else
        redborder[:segments][iface.to_sym][:master] = "n/a"
        redborder[:segments][iface.to_sym][:bypass] = false
      end
    end

    if `/usr/lib/redborder/bin/rb_bypass.sh -b #{iface} -g &>/dev/null; echo -n $?` == "1"
      redborder[:segments][iface.to_sym]["status"] = "bypass"
    else
      redborder[:segments][iface.to_sym]["status"] = "on"
    end

  end

  redborder[:has_bypass] = has_bypass

  netDir = Dir.open('/sys/class/net/')
  netDir.to_a.each do |iface|
    next if iface == "." or iface == ".."
    next unless iface =~ /^dna[02468]+$/
    dna_index  = iface.match(/^dna([\d]+)$/)[1].to_i
    if dna_index%2 == 0
      dna_bond_index = bond_index + dna_index / 2
      bypass = `bpctl_util #{iface} is_bypass|egrep -q "The interface is a control interface|The interface is a slave interface"; [ $? -eq 0 ] && echo 1 || echo 0`.chomp == "1"
      bond_iface = bypass ? "bpbr#{dna_bond_index}" : "br#{dna_bond_index}"
      redborder[:segments][bond_iface.to_sym]= Mash.new
      redborder[:segments][bond_iface.to_sym][:interfaces]={}

      [iface, "dna#{dna_index+1}"].each do |eth|
        thash={}
        thash[:status]=`cat /sys/class/net/#{eth.to_s}/operstate 2>/dev/null`.chomp
        thash[:type]=`ethtool #{eth.to_s} 2>/dev/null | grep "Supported ports:" | sed 's/Supported ports: //' | tr '[' ' ' | tr ']' ' ' | awk '{print $1}'`.chomp.downcase
        redborder[:segments][bond_iface.to_sym][:interfaces][eth.to_sym]=thash
      end

      if bypass
        redborder[:segments][bond_iface.to_sym][:master] = iface
        redborder[:segments][bond_iface.to_sym][:bypass] = (`bpctl_util #{iface} get_bypass|grep -q non-Bypass; [ $? -eq 0 ] && echo disabled || echo enabled`.chomp == "enabled")
      else
        redborder[:segments][bond_iface.to_sym][:master] = "n/a"
        redborder[:segments][bond_iface.to_sym][:bypass] = false
      end
    end
  end
end

domain=`/bin/hostname -d 2>/dev/null`.chomp
domain=`grep domain /etc/resolv.conf|awk '{print $2}'`.chomp if domain==""
domain=`grep search /etc/resolv.conf|awk '{print $2}'`.chomp if domain==""
domain="redborder.cluster" if domain==""

redborder[:domain]=domain
