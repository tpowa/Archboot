#! /bin/bash
_ARCH="aarch64"
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
_root_check
_update_aarch64_pacman_chroot || exit 1
_update_source
_server_release  || exit 1
