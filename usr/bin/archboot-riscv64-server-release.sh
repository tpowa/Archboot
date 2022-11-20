#! /bin/bash
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/server.sh
_root_check
_update_pacman_chroot || exit 1
_update_source
_server_release  || exit 1
