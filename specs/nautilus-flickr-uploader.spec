Name:           nautilus-flickr-uploader
Version:        0.02
Release:        1%{?dist}
Summary:        Upload pics to Flickr from Nautilus

Group:          Applications/Internet
License:        GPL+
URL:            http://www.usebox.net/jjm/nautilus-flickr-uploader/
Source0:        http://www.usebox.net/jjm/nautilus-flickr-uploader/SOURCES/%{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildArch:      noarch
BuildRequires:  perl(Gtk2), perl(Gtk2::GladeXML), perl(Gtk2::SimpleList)
BuildRequires:  perl(YAML)
BuildRequires:  perl(Flickr::API), perl(XML::Parser::Lite::Tree)
BuildRequires:  perl(Image::Magick)
BuildRequires:  perl(LWP::UserAgent)
BuildRequires:  gettext
BuildRequires:  perl(Locale::gettext)
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       nautilus

%description
This is a simple tool to upload pics to Flickr from Nautilus file browser.


%prep
%setup -q -n nautilus-flickr-uploader-%{version}

%build

%install
rm -rf $RPM_BUILD_ROOT
make pure_install DESTDIR=$RPM_BUILD_ROOT/usr

%find_lang %{name}

chmod -R u+w $RPM_BUILD_ROOT/*

%clean
rm -rf $RPM_BUILD_ROOT


%files -f %{name}.lang
%defattr(-,root,root,-)
%doc README TODO Changes COPYING INSTALL
%{_bindir}/nautilus-flickr-uploader
%{_datadir}/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg


%post
sed -i -e "s|-I./lib|-I%{_datadir}/%{name}/lib|g" %{_bindir}/nautilus-flickr-uploader
sed -i -e "s|./UI|%{_datadir}/%{name}/UI|g" %{_datadir}/%{name}/lib/Upload.pm
sed -i -e "s|./UI|%{_datadir}/%{name}/UI|g" %{_datadir}/%{name}/lib/Account.pm
sed -i -e "s|./bin|%{_bindir}|g" %{_datadir}/applications/nautilus-flickr-uploader.desktop
update-desktop-database %{_datadir}/applications &> /dev/null || :
gtk-update-icon-cache --quiet %{_datadir}/icons/hicolor || :

%postun
update-desktop-database %{_datadir}/applications &> /dev/null || :
gtk-update-icon-cache --quiet %{_datadir}/icons/hicolor || :

%changelog
* Wed Aug 27 2009 Juan J. Martinez <jjm@usebox.net> 0.02-1
- TODO
* Wed Aug 26 2009 Juan J. Martinez <jjm@usebox.net> 0.01-1
- first public release

