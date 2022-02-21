#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="aarch64"
source /usr/lib/archboot/functions
source /usr/lib/archboot/container_functions
source /etc/archboot/defaults
_LATEST_ARM64="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
_KEYRING="archlinuxarm"

_usage () {
    echo "CREATE AARCH64 PACMAN CHROOT"
    echo "-----------------------------"
    echo "This will create an aarch64 pacman chroot tarball on x86_64"
    echo "Usage: ${_BASENAME} <build-directory>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_root_check
_x86_64_check

echo "Starting container creation ..."
echo "Create directory ${1} ..."
mkdir -p "${1}"/"${_PACMAN_AARCH64}"
echo "Downloading archlinuxarm aarch64 ..."
! [[ -f ArchLinuxARM-aarch64-latest.tar.gz ]] && wget "${_LATEST_ARM64}" >/dev/null 2>&1
bsdtar -xf ArchLinuxARM-aarch64-latest.tar.gz -C "${1}"
echo "Removing installation tarball ..."
rm ArchLinuxARM-aarch64-latest.tar.gz
_generate_locales "${1}" || exit 1
_generate_keyring "${1}" || exit 1
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
# fix network in container
rm "${1}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${1}/etc/resolv.conf"
# update container to latest packages
echo "Installing pacman to container ..."
mkdir -p "${1}/${_PACMAN_AARCH64}/var/lib/pacman"
systemd-nspawn -D "${1}" pacman --root "/${_PACMAN_AARCH64}" -Sy awk pacman --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
# copy locale
echo "Copying locales to container ..."
cp "${1}/usr/lib/locale/locale-archive" "${1}/${_PACMAN_AARCH64}/usr/lib/locale/locale-archive" || exit 1
# generate pacman keyring
_generate_keyring "${1}/${_PACMAN_AARCH64}" || exit 1
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}/${_PACMAN_AARCH64}"/etc/pacman.conf
# fix network in container
rm "${1}/${_PACMAN_AARCH64}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${1}/${_PACMAN_AARCH64}/etc/resolv.conf"
_CLEANUP_CONTAINER="1" _clean_container "${1}/${_PACMAN_AARCH64}" || exit 1
_CLEANUP_CACHE="1" _clean_cache "${1}/${_PACMAN_AARCH64}" || exit 1
echo "Generating tarball ..."
tar -acf ${_PACMAN_AARCH64_CHROOT} -C "${1}"/"${_PACMAN_AARCH64}" . || exit 1
echo " Removing ${1} ..."
rm -r "${1}"
echo "Finished container tarball."
echo "Sign tarball ..."
sudo -u "${_USER}" gpg ${_GPG} ${_PACMAN_AARCH64_CHROOT} || exit 1
chown "${_USER}":${GROUP} ${_PACMAN_AARCH64_CHROOT}{,.sig} || exit 1
echo "Uploading tarball to ${_SERVER}:${_SERVER_PACMAN_AARCH64} ..."
sudo -u "${_USER}" scp ${_PACMAN_AARCH64_CHROOT}{,.sig} ${_SERVER}:${_SERVER_PACMAN_AARCH64} || exit 1

