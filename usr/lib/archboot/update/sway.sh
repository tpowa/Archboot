#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_sway() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_SWAY_PACKAGES}"
    _prepare_sway
}

_start_sway() {
    echo -e "Launching \e[1mSway\e[m now, logging is done on \e[1m/dev/tty7\e[m..."
    echo -e "To relaunch \e[1mSway\e[m use: \e[92msway-wayland\e[m"
    echo "MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland \
        XKB_DEFAULT_LAYOUT="$(grep 'KEYMAP' /etc/vconsole.conf | cut -d '=' -f2 | sed -e 's#-.*##g')" \
        exec dbus-run-session sway >/dev/tty7 2>&1" > /usr/bin/sway-wayland
    chmod 755 /usr/bin/sway-wayland
    sway-wayland
}
# vim: set ft=sh ts=4 sw=4 et:
