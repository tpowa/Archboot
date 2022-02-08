#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
export _ARCHBOOT="archboot-arm"
export _KEYRING=" archlinuxarm"
[[ -z "${1}" ]] && _usage
_DIR="$1"
#shellcheck disable=SC2120
_parameters
_root_check
echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir "${_DIR}"
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _prepare_pacman
    _install_base_packages
    _cleanmkinitcpio
    _cleancache
    _install_archboot
    _umount_special
    _cleancontainer
    _clean_archboot_cache
    _generate_keyring
    _generate_locales
    _clean_locale
    _copy_mirrorlist_and_pacman_conf
    _change_pacman_conf
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _aarch64_pacman_chroot
    _install_base_packages
    _cleanmkinitcpio
    _cleancache
    _install_archboot
    _cleanmkinitcpio
    _cleancache
    _cleancontainer
    _clean_locale
fi
_set_hostname
echo "Finished container setup in ${_DIR} ."
unset _ARCHBOOT
unset _KEYRING
