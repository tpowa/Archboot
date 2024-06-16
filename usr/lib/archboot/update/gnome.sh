#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_configure_gnome() {
    echo "Configuring Gnome..."
    echo "Setting wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal -- /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer lstopo qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        if [[ -f /usr/share/applications/"${i}".desktop ]]; then
            echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
            echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
        fi
    done
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        _prepare_graphic "${_PACKAGES}"
    fi
    _prepare_browser >"${_LOG}" 2>&1
    _configure_gnome >"${_LOG}" 2>&1
}

_install_gnome() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_GNOME_PACKAGES}"
    _prepare_gnome
}

_start_gnome() {
    _progress "100" "Launching GNOME Wayland now, logging is done on ${_LOG}..."
    sleep 2
    echo "MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland exec dbus-run-session gnome-session >${_LOG} 2>&1" > /usr/bin/gnome-wayland
    chmod 755 /usr/bin/gnome-wayland
    gnome-wayland
}
# vim: set ft=sh ts=4 sw=4 et:
