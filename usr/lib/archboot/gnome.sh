#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_GNOME_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop ..."
        _configure_gnome >/dev/tty7 2>&1
        systemd-sysusers >/dev/tty7 2>&1
        systemd-tmpfiles --create >/dev/tty7 2>&1
    else
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop already done ..."
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop already done ..."
    fi
}

_configure_gnome() {
    echo "Configuring Gnome ..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper ..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal -- /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer qvidcap qv4l2 lstopo"
    echo "Hiding ${_HIDE_MENU} menu entries ..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_start_gnome() {
    echo -e "Launching GNOME now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export XDG_SESSION_TYPE=x11" > /root/.xinitrc
    #shellcheck disable=SC2129
    echo "export GDK_BACKEND=x11" >> /root/.xinitrc
    echo "export LANG=C.UTF-8"  >> /root/.xinitrc
    echo "exec dbus-launch gnome-session" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch GNOME desktop use: \033[92mstartx\033[0m"
}
