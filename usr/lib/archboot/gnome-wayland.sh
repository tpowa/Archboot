#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome_wayland() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_GNOME_PACKAGES}"
    _prepare_gnome >/dev/tty7 2>&1
}

_start_gnome_wayland() {
    echo -e "Launching GNOME Wayland now, logging is done on \033[1m/dev/tty7\033[0m ..."
    echo -e "To relaunch GNOME Wayland use: \033[92mgnome-wayland\033[0m"

    echo "LANG=C.UTF-8 MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland exec dbus-run-session gnome-session >/dev/tty7 2>&1" > /usr/bin/gnome-wayland
    chmod 755 /usr/bin/gnome-wayland
    gnome-wayland
}
