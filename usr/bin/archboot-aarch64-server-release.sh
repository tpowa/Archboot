#! /bin/bash
_ARCH="aarch64"
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
_root_check
_buildserver_check
_update_aarch64_pacman_chroot
_server_release
