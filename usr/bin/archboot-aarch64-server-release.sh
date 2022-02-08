#! /bin/bash
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
_ARCH="aarch64"
_root_check
_check_buildserver
_update_aarch64_pacman_chroot
_server_release

