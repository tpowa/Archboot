#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_plasma() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma() {
    echo -e "Launching \e[1mKDE/Plasma\e[0m now, logging is done on \e[1m/dev/tty8\e[0m..."
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch \e[1mKDE/Plasma\e[0m desktop use: \e[92mstartx\e[0m"
}
# vim: set ft=sh ts=4 sw=4 et:
