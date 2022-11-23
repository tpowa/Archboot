#! /bin/bash
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/server.sh
_root_check
_container_check
if echo "${_BASENAME}" | grep -qw riscv64 || echo "${_BASENAME}" | grep -qw aarch64; then
    _update_pacman_chroot || exit 1
fi
_update_source
if echo "${_BASENAME}" | grep -qw x86_64; then
    _x86_64_pacman_use_default || exit 1
fi
_server_release || exit 1
if echo "${_BASENAME}" | grep -qw x86_64; then
    _x86_64_pacman_restore || exit 1
fi
