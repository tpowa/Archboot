#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
_CACHEDIR="${1}/var/cache/pacman/pkg"
_ARCHBOOT="archboot"
_KEYRING="archlinux"
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_x86_64_check
echo "Starting container creation ..."
[[ -d "${1}" ]] || (echo "Create directory ${1} ..."; mkdir "${1}")
_create_pacman_conf "${1}"
_prepare_pacman "${1}" || exit 1
_install_base_packages "${1}" || exit 1
_clean_mkinitcpio "${1}" || exit 1
_clean_cache "${1}" || exit 1
_install_archboot "${1}" || exit 1
_umount_special "${1}" || exit 1
_generate_locales "${1}" || exit 1
_clean_locale "${1}"
_clean_container "${1}" || exit 1
_clean_archboot_cache
_generate_keyring "${1}" || exit 1
_copy_mirrorlist_and_pacman_conf "${1}"
_change_pacman_conf "${1}" || exit 1
# enable [testing] if enabled in host
if grep -q "^\[testing" /etc/pacman.conf; then
    echo "Enable [testing] repository in container ..."
    sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${1}/etc/pacman.conf"
    sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${1}/etc/pacman.conf"
    sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${1}/etc/pacman.conf"
fi
_set_hostname "${1}" || exit 1
echo "Finished container setup in ${1} ."

