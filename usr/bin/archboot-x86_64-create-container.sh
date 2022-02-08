#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
export _ARCHBOOT="archboot"
export _KEYRING="archlinux"
[[ -z "${1}" ]] && _usage
_DIR="$1"
#shellcheck disable=SC2120
_parameters
_root_check
_x86_64_check
echo "Starting container creation ..."
echo "Create directories in ${_DIR} ..."
_prepare_pacman
_install_base_packages
_cleanmkinitcpio
_cleancache
_install_archboot
_umount_special
_cleancontainer
_clean_archboot_cache
_generate_locales
_clean_locale
_generate_keyring
_copy_mirrorlist_and_pacman_conf
_change_pacman_conf
# enable [testing] if enabled in host
if grep -q "^\[testing" /etc/pacman.conf; then
    echo "Enable [testing] repository in container ..."
    sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${_DIR}/etc/pacman.conf"
    sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${_DIR}/etc/pacman.conf"
    sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${_DIR}/etc/pacman.conf"
fi
_set_hostname
echo "Finished container setup in ${_DIR} ."
unset _ARCHBOOT
unset _KEYRING
