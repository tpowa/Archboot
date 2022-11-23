#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_plasma() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma() {
    echo -e "Launching \033[1mKDE/Plasma\033[0m now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch \033[1mKDE/Plasma\033[0m desktop use: \033[92mstartx\033[0m"
}
