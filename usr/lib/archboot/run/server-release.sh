#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/server.sh
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_root_check
_container_check
if rg -qw 'riscv64' <<< "${_BASENAME}" || rg -qw 'aarch64' <<< "${_BASENAME}"; then
    _update_pacman_container || exit 1
fi
_update_source
if rg -qw 'x86_64' <<< "${_BASENAME}"; then
    _x86_64_pacman_use_default || exit 1
fi
_server_release || exit 1
if rg -qw 'x86_64' <<< "${_BASENAME}"; then
    _x86_64_pacman_restore || exit 1
fi
