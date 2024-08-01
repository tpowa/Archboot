#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/server.sh
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_root_check
_container_check
if echo "${_BASENAME}" | rg -qw 'riscv64' || echo "${_BASENAME}" | rg -qw 'aarch64'; then
    _update_pacman_container || exit 1
fi
_update_source
if echo "${_BASENAME}" | rg -qw 'x86_64'; then
    _x86_64_pacman_use_default || exit 1
fi
_server_release || exit 1
if echo "${_BASENAME}" | rg -qw 'x86_64'; then
    _x86_64_pacman_restore || exit 1
fi
# vim: set ft=sh ts=4 sw=4 et:
