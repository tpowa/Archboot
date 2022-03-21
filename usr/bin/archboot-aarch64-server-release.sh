#! /bin/bash
_ARCH="aarch64"
source /usr/lib/archboot/common.sh
source /usr/lib/archboot/server.sh
_root_check
_update_aarch64_pacman_chroot || exit 1
_update_source
_server_release  || exit 1
