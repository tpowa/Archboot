#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_kde() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE desktop now ..."
        echo "          This will need some time ..."
        _prepare_x "${_KDE_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop ..."
        _configure_kde >/dev/tty7 2>&1
    fi
}

_start_kde() {
    echo -e "Launching KDE now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo startplasma-x11 > /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch KDE desktop use: \033[92mstartx\033[0m"
}

_configure_kde() {
    echo "Configuring KDE panel ..."
    #echo "Adding gparted to xfce top level menu ..."
    #sed -i -e 's#Categories=.*#Categories=X-Xfce-Toplevel;#g' /usr/share/applications/gparted.desktop
    #echo "Hiding ${_HIDE_MENU} menu entries ..."
    #for i in ${_HIDE_MENU}; do
    #    echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    #done
    #echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
Exec=konsoleprofile colors=Linux;konsole -e /usr/bin/setup
Icon=system-software-install
EOF
}
