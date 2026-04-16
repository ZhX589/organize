Name:           organize
Version:        %{?version:2.0.0}%{!?version:2.0.0}
Release:        1%{?dist}
Summary:        File organizer by extension

License:        MIT
URL:            https://github.com/yourusername/organize
Source0:        organize.sh
Source1:        rules.conf.example
Source2:        organize.1

BuildArch:      noarch
Requires:       bash >= 4.0, coreutils

%description
Automatically sort files in a directory based on customizable rules.
Supports dry-run, custom rules, temporary file cleaning, and more.

%install
mkdir -p %{buildroot}%{_bindir}
install -m755 %{SOURCE0} %{buildroot}%{_bindir}/organize

mkdir -p %{buildroot}%{_datadir}/organize
install -m644 %{SOURCE1} %{buildroot}%{_datadir}/organize/rules.conf.default

mkdir -p %{buildroot}%{_mandir}/man1
install -m644 %{SOURCE2} %{buildroot}%{_mandir}/man1/organize.1

%files
%{_bindir}/organize
%{_datadir}/organize/
%{_mandir}/man1/organize.1.gz

%changelog
* Thu Apr 16 2026 Your Name <your.email@example.com> - 2.0.0-1
- Initial package
