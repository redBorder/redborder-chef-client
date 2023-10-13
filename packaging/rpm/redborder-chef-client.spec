Name: redborder-chef-client
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Redborder package containing chef-client files

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-chef-client
Source0: %{name}-%{version}.tar.gz

BuildRequires: systemd

Requires: bash redborder-rubyrvm

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/chef
install -D -m 0644 resources/conf/client.rb.default %{buildroot}/etc/chef/client.rb.default
install -D -m 0644 resources/conf/knife.rb.default %{buildroot}/etc/chef/knife.rb.default
mkdir -p %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/bin/rb_chef-client_start.sh %{buildroot}/usr/lib/redborder/bin/rb_chef-client_start.sh
install -D -m 0644 resources/systemd/chef-client.service %{buildroot}/usr/lib/systemd/system/chef-client.service
mkdir -p %{buildroot}/etc/chef/ohai_plugins/
install -D -m 0644 resources/ohai_plugins/redborder.rb %{buildroot}/etc/chef/ohai_plugins/redborder.rb

%files
%defattr(0644,root,root)
/etc/chef/client.rb.default
/etc/chef/knife.rb.default
%defattr(0755,root,root)
/usr/lib/redborder/bin/rb_chef-client_start.sh
%defattr(0644,root,root)
/usr/lib/systemd/system/chef-client.service
/etc/chef/ohai_plugins/redborder.rb

%post
%systemd_post chef-client.service

%changelog
* Thu Aug 30 2016 Carlos J. Mateos <cjmateos@redborder.com> 1.0.0-4
- Add chef client config files

* Wed Jul 28 2016 Enrique Jimenez <ejimenez@redborder.com> 1.0.0-3
- Added systemd script

* Wed Jul 28 2016 Enrique Jimenez <ejimenez@redborder.com> 1.0.0-2
- Added wrapper script

* Wed Jul 28 2016 Enrique Jimenez <ejimenez@redborder.com> 1.0.0-1
- first spec version
