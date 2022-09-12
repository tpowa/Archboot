#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="riscv64"
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
_RISCV64_VERSION="archriscv-20220727"
_LATEST_RISCV64="https://archriscv.felixc.at/images/${_RISCV64_VERSION}.tar.zst"
_KEYRING="archlinux"

_usage () {
    echo "CREATE RISCV64 PACMAN CHROOT"
    echo "-----------------------------"
    echo "This will create an riscv64 pacman chroot tarball on x86_64"
    echo "Usage: ${_BASENAME} <build-directory>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_root_check
_x86_64_check

echo "Starting container creation ..."
# remove old files
[[ -f ${_PACMAN_RISCV64_CHROOT} ]] && rm ${_PACMAN_RISCV64_CHROOT}{,.sig} 2>/dev/null
echo "Create directory ${1} ..."
mkdir -p "${1}"/"${_PACMAN_RISCV64}"
echo "Downloading archlinux riscv64 ..."
! [[ -f ${_RISCV64_VERSION}.tar.zst ]] && wget "${_LATEST_RISCV64}" >/dev/null 2>&1
bsdtar -xf ${_RISCV64_VERSION}.tar.zst -C "${1}"
echo "Removing installation tarball ..."
rm ${_RISCV64_VERSION}.tar.zst
_generate_keyring "${1}" || exit 1
_fix_network "${1}"
# update container to latest packages
echo "Installing pacman to container ..."
mkdir -p "${1}/${_PACMAN_RISCV64}/var/lib/pacman"
systemd-nspawn -D "${1}" pacman --root "/${_PACMAN_RISCV64}" -Sy awk pacman archlinux-keyring --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
_generate_keyring "${1}/${_PACMAN_RISCV64}" || exit 1
_fix_network "${1}/${_PACMAN_RISCV64}"
_CLEANUP_CONTAINER="1" _clean_container "${1}/${_PACMAN_RISCV64}" 2>/dev/null
_CLEANUP_CACHE="1" _clean_cache "${1}/${_PACMAN_RISCV64}" 2>/dev/null
echo "Generating tarball ..."
tar -acf ${_PACMAN_RISCV64_CHROOT} -C "${1}"/"${_PACMAN_RISCV64}" . >/dev/null 2>&1 || exit 1
echo "Removing ${1} ..."
rm -r "${1}"
echo "Finished container tarball."
echo "Sign tarball ..."
#shellcheck disable=SC2086
sudo -u "${_USER}" gpg ${_GPG} ${_PACMAN_RISCV64_CHROOT} || exit 1
chown "${_USER}":"${_GROUP}" ${_PACMAN_RISCV64_CHROOT}{,.sig} || exit 1
echo "Uploading tarball to ${_SERVER}:${_SERVER_PACMAN_RISCV64} ..."
sudo -u "${_USER}" scp ${_PACMAN_RISCV64_CHROOT}{,.sig} ${_SERVER}:${_SERVER_PACMAN_RISCV64} || exit 1
echo "Finished."
