#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_plasma() {
    _PACKAGES="${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma() {
    _progress "100" "Launching Plasma/KDE now, logging is done on /dev/tty8..."
    sleep 2
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
}
# vim: set ft=sh ts=4 sw=4 et:
