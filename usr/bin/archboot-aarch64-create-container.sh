#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
_PACMAN_AARCH64_CHROOT_SERVER="https://pkgbuild.com/~tpowa/archboot-helper/pacman-chroot-aarch64"
_PACMAN_AARCH64_CHROOT="pacman-aarch64-chroot-latest.tar.zst"
_ARCHBOOT="archboot-arm"
_KEYRING=" archlinuxarm"
[[ -z "${1}" ]] && _usage
_DIR="$1"
#shellcheck disable=SC2120
_parameters
_root_check
echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir "${_DIR}"
if [[ "$(uname -m)" == "aarch64" ]]; then
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
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "Downloading archlinuxarm pacman aarch64 chroot..."
    [[ -f pacman-aarch64-chroot-latest.tar.zst ]] || wget ${_PACMAN_AARCH64_CHROOT_SERVER}/${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
    # verify dowload
    sleep 1
    gpg --verify "${_PACMAN_AARCH64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${_DIR}" -xf "${_PACMAN_AARCH64_CHROOT}"
    echo "Removing installation tarball ..."
    rm ${_PACMAN_AARCH64_CHROOT}{,.sig}
    # update container to latest packages
    echo "Update container to latest packages..."
    systemd-nspawn -D "${_DIR}" pacman -Syu --noconfirm >/dev/null 2>&1
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
