#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
if echo "${_BASENAME}" | rg -qw 'aarch64'; then
    _PACMAN_ARCH_CHROOT="${_PACMAN_AARCH64_CHROOT}"
    _PACMAN_ARCH="${_PACMAN_AARCH64}"
    _ARCH_VERSION="ArchLinuxARM-aarch64-latest.tar.gz"
    _SERVER_PACMAN_ARCH="${_SERVER_PACMAN_AARCH64}"
    _LATEST_ARCH="http://os.archlinuxarm.org/os/${_ARCH_VERSION}"
    _CAP_ARCH="AARCH64"
    _ARCH="aarch64"
elif echo "${_BASENAME}" | rg -qw 'riscv64'; then
    _PACMAN_ARCH_CHROOT="${_PACMAN_RISCV64_CHROOT}"
    _PACMAN_ARCH="${_PACMAN_RISCV64}"
    _ARCH_VERSION="archriscv-20220727.tar.zst"
    _SERVER_PACMAN_ARCH="${_SERVER_PACMAN_RISCV64}"
    _LATEST_ARCH="https://archriscv.felixc.at/images/${_ARCH_VERSION}"
    _CAP_ARCH="RISCV64"
    _ARCH="riscv64"
fi

_usage () {
    echo "CREATE ${_CAP_ARCH} PACMAN CHROOT"
    echo "-----------------------------"
    echo "This will create the ${_ARCH} pacman container tarball."
    echo "usage: ${_BASENAME} <build-directory>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_root_check

echo "Starting container creation..."
# remove old files
[[ -f ${_PACMAN_ARCH_CHROOT} ]] && rm "${_PACMAN_ARCH_CHROOT}"{,.sig} 2>"${_NO_LOG}"
echo "Creating directory ${1}..."
mkdir -p "${1}"/"${_PACMAN_ARCH}"
echo "Downloading archlinux ${_ARCH}..."
! [[ -f ${_ARCH_VERSION} ]] && ${_DLPROG} -O "${_LATEST_ARCH}"
bsdtar -xf "${_ARCH_VERSION}" -C "${1}"
echo "Removing installation tarball..."
rm "${_ARCH_VERSION}"
_generate_keyring "${1}" || exit 1
_fix_network "${1}"
# update container to latest packages
echo "Installing pacman to container..."
mkdir -p "${1}/${_PACMAN_ARCH}${_PACMAN_LIB}"
#shellcheck disable=SC2086
systemd-nspawn -D "${1}" pacman --root "/${_PACMAN_ARCH}" -Sy awk ${_KEYRING} \
               --ignore systemd-resolvconf --noconfirm &>"${_NO_LOG}"
_generate_keyring "${1}/${_PACMAN_ARCH}" || exit 1
_fix_network "${1}/${_PACMAN_ARCH}"
_CLEANUP_CONTAINER="1" _clean_container "${1}/${_PACMAN_ARCH}" 2>"${_NO_LOG}"
_CLEANUP_CACHE="1" _clean_cache "${1}/${_PACMAN_ARCH}" 2>"${_NO_LOG}"
echo "Generating tarball..."
tar -acf "${_PACMAN_ARCH_CHROOT}" -C "${1}"/"${_PACMAN_ARCH}" . &>"${_NO_LOG}" || exit 1
echo "Removing ${1}..."
rm -r "${1}"
echo "Finished container tarball."
echo "Signing tarball..."
#shellcheck disable=SC2086
run0 -u "${_USER}" gpg ${_GPG} ${_PACMAN_ARCH_CHROOT} || exit 1
chown "${_USER}":"${_GROUP}" "${_PACMAN_ARCH_CHROOT}"{,.sig} || exit 1
echo "Syncing tarball to ${_SERVER}:${_PUB}/.${_SERVER_PACMAN_ARCH}..."
#shellcheck disable=SC2086
run0 -u "${_USER}" ${_RSYNC} "${_PACMAN_ARCH_CHROOT}"{,.sig} "${_SERVER}:${_PUB}/.${_SERVER_PACMAN_ARCH}" || exit 1
echo "Finished."
# vim: set ft=sh ts=4 sw=4 et:
