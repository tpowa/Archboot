#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_x "${_GNOME_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop ..."
        _configure_gnome >/dev/tty7 2>&1
    fi
}

_configure_gnome() {
    echo "Configuring Gnome ..."
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'gparted.desktop', 'chromium.desktop',  'archboot.desktop']"
    echo "Setting wallpaper ..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_start_gnome() {
    echo -e "Launching GNOME now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export XDG_SESSION_TYPE=x11" > /root/.xinitrc
    echo "export GDK_BACKEND=x11" >> /root/.xinitrc
    echo "gnome-session" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch GNOME desktop use: \033[92mstartx\033[0m"
}
