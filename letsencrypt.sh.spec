Name:		letsencrypt.sh
Version:	0.0.1
Release:	1%{?dist}
Summary:	letsencrypt/acme client implemented as a shell-script

License:	MIT	
URL:		https://github.com/NethServer/letsencrypt.sh
Source0:	https://github.com/NethServer/letsencrypt.sh/archive/master.tar.gz

BuildArch:	noarch
Requires:	openssl

%description
letsencrypt/acme client implemented as a shell-script

%prep
%setup -n master


%build
rm -rf %{buildroot}
#mkdir -p %{buildroot}/usr/share/doc/%{name}-%{version}

%install
install -D -m 0555 letsencrypt.sh %{buildroot}/%{_sbindir}/letsencrypt.sh
install -D -m 0644 config.sh.example %{buildroot}/%{_sysconfdir}/%{name}/config.sh
install -D -m 0644 domains.txt.example %{buildroot}/%{_sysconfdir}/%{name}/domains.txt
install -D -m 0644 hook.sh.example %{buildroot}/%{_sysconfdir}/%{name}/hook.sh.example


%files
%dir %{_sysconfdir}/%{name}
%config %{_sysconfdir}/%{name}/config.sh
%config %{_sysconfdir}/%{name}/domains.txt
%ghost %{_sysconfdir}/%{name}/hook.sh.example
%doc README.md LICENSE
%{_sbindir}/letsencrypt.sh



%changelog
* Tue Feb 16 2016 Giacomo Sanchietti <giacomo.sanchietti@nethesis.it> - 0.0.1-1
- First build for CentOS

