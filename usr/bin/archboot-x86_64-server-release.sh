#! /bin/bash
_ARCH="x86_64"
source /usr/lib/archboot/common.sh
source /usr/lib/archboot/server.sh
_root_check
_update_source
_x86_64_pacman_use_default || exit 1
_server_release || exit 1
_x86_64_pacman_restore || exit 1
