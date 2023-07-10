#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_sway() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_SWAY_PACKAGES}"
    _prepare_sway
}

_start_sway() {
    echo -e "Launching \e[1mSway\e[m now..."
	echo -e "To relaunch \e[1mSway\e[m use: \e[92msway\e[m"
    sway
}
# vim: set ft=sh ts=4 sw=4 et:
