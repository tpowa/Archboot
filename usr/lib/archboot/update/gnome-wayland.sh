#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_gnome_wayland() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_GNOME_PACKAGES}"
    _prepare_gnome
}

_start_gnome_wayland() {
    echo -e "Launching \e[1mGNOME Wayland\e[m now, logging is done on \e[1m/dev/tty7\e[m..."
    echo -e "To relaunch \e[1mGNOME Wayland\e[m use: \e[92mgnome-wayland\e[m"

    echo "MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland exec dbus-run-session gnome-session >/dev/tty7 2>&1" > /usr/bin/gnome-wayland
    chmod 755 /usr/bin/gnome-wayland
    gnome-wayland
}
# vim: set ft=sh ts=4 sw=4 et:
