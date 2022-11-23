#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
if echo "${0}" | grep -qw aarch64; then
    _PACMAN_ARCH_CHROOT="${_PACMAN_AARCH64_CHROOT}"
    _PACMAN_ARCH="${_PACMAN_AARCH64}"
    _ARCH_VERSION="ArchLinuxARM-aarch64-latest.tar.gz"
    _SERVER_PACMAN_ARCH="${_SERVER_PACMAN_AARCH64}"
    _LATEST_ARCH="http://os.archlinuxarm.org/os/${_ARCH_VERSION}"
    _CAP_ARCH="AARCH64"
    _ARCH="aarch64"
else
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
    echo "This will create the ${_ARCH} pacman chroot tarball."
    echo "Usage: ${_BASENAME} <build-directory>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_root_check

echo "Starting container creation ..."
# remove old files
[[ -f ${_PACMAN_ARCH_CHROOT} ]] && rm ${_PACMAN_ARCH_CHROOT}{,.sig} 2>/dev/null
echo "Create directory ${1} ..."
mkdir -p "${1}"/"${_PACMAN_ARCH}"
echo "Downloading archlinux riscv64 ..."
! [[ -f ${_ARCH_VERSION} ]] && wget "${_LATEST_ARCH}" >/dev/null 2>&1
bsdtar -xf ${_ARCH_VERSION} -C "${1}"
echo "Removing installation tarball ..."
rm ${_ARCH_VERSION}
_generate_keyring "${1}" || exit 1
_fix_network "${1}"
# update container to latest packages
echo "Installing pacman to container ..."
mkdir -p "${1}/${_PACMAN_ARCH}/var/lib/pacman"
systemd-nspawn -D "${1}" pacman --root "/${_PACMAN_ARCH}" -Sy awk ${_KEYRING} --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
_generate_keyring "${1}/${_PACMAN_ARCH}" || exit 1
_fix_network "${1}/${_PACMAN_ARCH}"
_CLEANUP_CONTAINER="1" _clean_container "${1}/${_PACMAN_ARCH}" 2>/dev/null
_CLEANUP_CACHE="1" _clean_cache "${1}/${_PACMAN_ARCH}" 2>/dev/null
echo "Generating tarball ..."
tar -acf ${_PACMAN_ARCH_CHROOT} -C "${1}"/"${_PACMAN_ARCH}" . >/dev/null 2>&1 || exit 1
echo "Removing ${1} ..."
rm -r "${1}"
echo "Finished container tarball."
echo "Sign tarball ..."
#shellcheck disable=SC2086
sudo -u "${_USER}" gpg ${_GPG} ${_PACMAN_ARCH_CHROOT} || exit 1
chown "${_USER}":"${_GROUP}" ${_PACMAN_ARCH_CHROOT}{,.sig} || exit 1
echo "Uploading tarball to ${_SERVER}:${_SERVER_PACMAN_ARCH} ..."
sudo -u "${_USER}" scp ${_PACMAN_ARCH_CHROOT}{,.sig} ${_SERVER}:${_SERVER_PACMAN_ARCH} || exit 1
echo "Finished."
