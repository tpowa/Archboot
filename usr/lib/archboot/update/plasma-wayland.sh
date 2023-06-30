#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_plasma_wayland() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}"
    _prepare_plasma
}

_start_plasma_wayland() {
    echo -e "Launching \e[1mKDE/Plasma Wayland\e[m now, logging is done on \e[1m/dev/tty7\e[m..."
	echo -e "To relaunch \e[1mKDE/Plasma Wayland\e[m use: \e[92mplasma-wayland\e[m"
    echo "exec dbus-run-session startplasma-wayland >/dev/tty7 2>&1" > /usr/bin/plasma-wayland
    chmod 755 /usr/bin/plasma-wayland
    plasma-wayland
}
# vim: set ft=sh ts=4 sw=4 et:
