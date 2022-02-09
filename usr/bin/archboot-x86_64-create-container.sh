#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
_ARCHBOOT="archboot"
_KEYRING="archlinux"
[[ -z "${1}" ]] && _usage
_DIR="$1"
_parameters "$@"
_root_check
_x86_64_check
echo "Starting container creation ..."
echo "Create directories in ${_DIR} ..."
_prepare_pacman || exit 1
_install_base_packages || exit 1
_clean_mkinitcpio || exit 1
_clean_cache || exit 1
_install_archboot || exit 1
_umount_special || exit 1
_clean_container || exit 1
_clean_archboot_cache
_generate_locales || exit 1
_clean_locale
_generate_keyring || exit 1
_copy_mirrorlist_and_pacman_conf
_change_pacman_conf || exit 1
# enable [testing] if enabled in host
if grep -q "^\[testing" /etc/pacman.conf; then
    echo "Enable [testing] repository in container ..."
    sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${_DIR}/etc/pacman.conf"
    sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${_DIR}/etc/pacman.conf"
    sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${_DIR}/etc/pacman.conf"
fi
_set_hostname || exit 1
echo "Finished container setup in ${_DIR} ."

