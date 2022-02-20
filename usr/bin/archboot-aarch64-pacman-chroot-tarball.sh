#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
_LATEST_ARM64="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
_PACMAN_CHROOT="pacman-aarch64-chroot"
_KEYRING="archlinuxarm"

_usage () {
    echo "CREATE AARCH64 PACMAN CHROOT"
    echo "-----------------------------"
    echo "This will create an aarch64 pacman chroot tarball on x86_64"
    echo "Usage: ${_BASENAME} <directory>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_root_check
_x86_64_check

echo "Starting container creation ..."
echo "Create directory ${1} ..."
mkdir -p "${1}"/"${_PACMAN_CHROOT}"
echo "Downloading archlinuxarm aarch64..."
! [[ -f ArchLinuxARM-aarch64-latest.tar.gz ]] && wget "${_LATEST_ARM64}" >/dev/null 2>&1
bsdtar -xf ArchLinuxARM-aarch64-latest.tar.gz -C "${1}"
echo "Removing installation tarball ..."
rm ArchLinuxARM-aarch64-latest.tar.gz
_generate_locales "${1}"
_generate_keyring "${1}"
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
# fix network in container
rm "${1}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${1}/etc/resolv.conf"
# update container to latest packages
echo "Installing pacman to container ..."
mkdir -p "${1}/${_PACMAN_CHROOT}/var/lib/pacman"
sleep 1
systemd-nspawn -D "${1}" pacman --root "/${_PACMAN_CHROOT}" -Sy awk pacman --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
# generate pacman keyring
echo "Generate pacman keyring in container ..."
systemd-nspawn -D "${1}/${_PACMAN_CHROOT}" pacman-key --init >/dev/null 2>&1
systemd-nspawn -D "${1}/${_PACMAN_CHROOT}" pacman-key --populate archlinuxarm >/dev/null 2>&1
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}/${_PACMAN_CHROOT}"/etc/pacman.conf
# copy locale
echo "Copying locales to container ..."
cp "${1}/usr/lib/locale/locale-archive" "${1}/${_PACMAN_CHROOT}/usr/lib/locale/locale-archive"
# fix network in container
rm "${1}/${_PACMAN_CHROOT}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${1}/${_PACMAN_CHROOT}/etc/resolv.conf"
echo "Clean container, delete not needed files from ${1}/${_PACMAN_CHROOT} ..."
rm -r "${1}/${_PACMAN_CHROOT}"/usr/include
rm -r "${1}/${_PACMAN_CHROOT}"/usr/share/{man,doc,info}
echo "Generating tarball ..."
tar -acf ${_PACMAN_CHROOT}-latest.tar.zst -C "${1}"/"${_PACMAN_CHROOT}" .
echo " Removing ${1} ..."
rm -r "${1}"
echo "Finished container tarball."

