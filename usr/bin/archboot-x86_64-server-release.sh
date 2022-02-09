#! /bin/bash
_ARCH="x86_64"
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
_root_check
_buildserver_check
_x86_64_pacman_use_default
_server_release
_x86_64_pacman_restore
