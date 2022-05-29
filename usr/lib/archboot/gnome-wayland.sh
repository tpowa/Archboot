#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome_wayland() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_GNOME_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop ..."
        _configure_gnome_wayland >/dev/tty7 2>&1
        systemd-sysusers >/dev/tty7 2>&1
        systemd-tmpfiles --create >/dev/tty7 2>&1
    fi
}

_configure_gnome_wayland() {
    echo "Configuring Gnome ..."
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
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
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries ..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_start_gnome_wayland() {
    echo -e "Launching GNOME Wayland now, logging is done on \033[1m/dev/tty7\033[0m ..."
    LANG=C.UTF-8 MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland exec dbus-run-session gnome-session >/dev/tty7 2>&1
    echo -e "To relaunch GNOME Wayland use: \033[92mupdate-installer.sh -gnome-wayland\033[0m"
}
