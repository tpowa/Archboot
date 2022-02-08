#! /bin/bash
source /usr/lib/archboot/functions
source /usr/lib/archboot/server_functions
_ARCH="x86_64"
_check_root
_check_buildserver
_pacman_x86_64_use_default
_server_release
_pacman_x86_64_restore


