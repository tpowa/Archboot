#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_x "${_GNOME_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop ..."
        _configure_gnome >/dev/tty7 2>&1
    fi
}

_start_gnome() {
    echo -e "Launching KDE now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch KDE desktop use: \033[92mstartx\033[0m"
}

_configure_gnome() {
    echo "Configuring KDE ..."
    #sed -i -e 's#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,preferred://browser,applications:gparted.desktop,applications:archboot.desktop</default>#g' /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper ..."
    #for i in /usr/share/wallpapers/Next/contents/images/*; do
    #    cp /usr/share/archboot/grub/archboot-background.png $i
    #done
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal /usr/bin/setup
Icon=system-software-install
EOF
}
