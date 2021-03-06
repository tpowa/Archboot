#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_kde() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_PLASMA_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop ..."
        _configure_kde >/dev/tty7 2>&1
	else
		echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop already done ..."
		echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop already done ..."
    fi
}

_configure_kde() {
    echo "Configuring KDE ..."
    sed -i -e 's#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,preferred://browser,applications:gparted.desktop,applications:archboot.desktop</default>#g' /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper ..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure ..."
    cat << EOF >/etc/xdg/menus/applications.menu
 <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<!-- Search the default locations -->
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Separator/>
		<Menuname>More</Menuname>
	</DefaultLayout>
	<Layout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Menuname>Applications</Menuname>
	</Layout>
	<Menu>
		<Name>Settingsmenu</Name>
		<Directory>kf5-settingsmenu.directory</Directory>
		<Include>
			<Category>Settings</Category>
		</Include>
	</Menu>
	<DefaultMergeDirs/>
	<Include>
	<Filename>archboot.desktop</Filename>
	<Filename>chromium.desktop</Filename>
	<Filename>org.kde.dolphin.desktop</Filename>
	<Filename>gparted.desktop</Filename>
	<Filename>org.kde.konsole.desktop</Filename>
	</Include>
</Menu>
EOF
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=konsole -p colors=Linux -e /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_start_kde() {
    echo -e "Launching KDE/Plasma now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch KDE desktop use: \033[92mstartx\033[0m"
}
