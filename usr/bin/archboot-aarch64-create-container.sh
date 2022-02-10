#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
_ARCHBOOT="archboot-arm"
_KEYRING="archlinuxarm"
[[ -z "${1}" ]] && _usage
_DIR="$1"
_parameters "$@"
_root_check
echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir "${_DIR}"
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _prepare_pacman || exit 1
    _install_base_packages || exit 1
    _clean_mkinitcpio || exit 1
    _clean_cache || exit 1
    _install_archboot || exit 1
    _umount_special || exit 1
    _clean_container || exit 1
    _clean_archboot_cache
    _generate_keyring || exit 1
    _generate_locales || exit 1
    _clean_locale
    _copy_mirrorlist_and_pacman_conf
    _change_pacman_conf || exit 1
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _aarch64_pacman_chroot || exit 1
    _aarch64_install_base_packages || exit 1
    _clean_mkinitcpio || exit 1
    _clean_cache || exit 1
    _aarch64_install_archboot || exit 1
    _clean_mkinitcpio || exit 1
    _clean_cache || exit 1
    _clean_container || exit 1
    _generate_locales || exit 1
    _clean_locale
fi
_set_hostname || exit 1
echo "Finished container setup in ${_DIR} ."
