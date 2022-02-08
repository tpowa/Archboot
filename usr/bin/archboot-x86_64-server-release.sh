#! /bin/bash
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
export _ARCH="x86_64"
_root_check
_buildserver_check
_pacman_x86_64_use_default
_server_release
_pacman_x86_64_restore
unset _ARCH

