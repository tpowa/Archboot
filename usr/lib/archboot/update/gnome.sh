#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_gnome() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_GNOME_PACKAGES}"
    _prepare_gnome
}

_start_gnome() {
    echo -e "Launching \e[1mGNOME\e[m now, logging is done on \e[1m/dev/tty8\e[m..."
    echo "export XDG_SESSION_TYPE=x11" > /root/.xinitrc
    #shellcheck disable=SC2129
    echo "export GDK_BACKEND=x11" >> /root/.xinitrc
    echo "exec dbus-launch gnome-session" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch \e[1mGNOME\e[m desktop use: \e[92mstartx\e[m"
}
# vim: set ft=sh ts=4 sw=4 et:
