#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_gnome() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_GNOME_PACKAGES}"
    _prepare_gnome
}

_start_gnome() {
    echo -e "Launching \033[1mGNOME\033[0m now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export XDG_SESSION_TYPE=x11" > /root/.xinitrc
    #shellcheck disable=SC2129
    echo "export GDK_BACKEND=x11" >> /root/.xinitrc
    echo "export LANG=C.UTF-8"  >> /root/.xinitrc
    echo "exec dbus-launch gnome-session" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch \033[1mGNOME\033[0m desktop use: \033[92mstartx\033[0m"
}
