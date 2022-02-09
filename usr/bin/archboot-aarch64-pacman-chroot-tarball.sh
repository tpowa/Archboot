#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
_DIR=""
_LATEST_ARM64="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
_PACMAN_CHROOT="pacman-aarch64-chroot"
_KEYRING="archlinuxarm"

_usage () {
    echo "CREATE AARCH64 PACMAN CHROOT"
    echo "-----------------------------"
    echo "This will create an aarch64 pacman chroot tarball on x86_64"
    echo "Usage: ${_BASENAME} <directory> <options>"
    exit 0
}

[[ -z "${1}" ]] && _usage

_DIR="$1"

while [ $# -gt 0 ]; do
    case ${1} in
        -cc|--cc) _SAVE_RAM="1" ;;
    esac
    shift
done

_root_check
_x86_64_check

echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir -p "${_DIR}"/"${_PACMAN_CHROOT}"
echo "Downloading archlinuxarm aarch64..."
! [[ -f ArchLinuxARM-aarch64-latest.tar.gz ]] && wget "${_LATEST_ARM64}" >/dev/null 2>&1
bsdtar -xf ArchLinuxARM-aarch64-latest.tar.gz -C "${_DIR}"
echo "Removing installation tarball ..."
rm ArchLinuxARM-aarch64-latest.tar.gz
_generate_locales
_generate_keyring
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}"/etc/pacman.conf
# fix network in container
rm "${_DIR}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${_DIR}/etc/resolv.conf"
# update container to latest packages
echo "Installing pacman to container ..."
mkdir -p "${_DIR}/${_PACMAN_CHROOT}/var/lib/pacman"
sleep 1
systemd-nspawn -D "${_DIR}" pacman --root "/${_PACMAN_CHROOT}" -Sy awk pacman --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
# generate pacman keyring
echo "Generate pacman keyring in container ..."
systemd-nspawn -D "${_DIR}/${_PACMAN_CHROOT}" pacman-key --init >/dev/null 2>&1
systemd-nspawn -D "${_DIR}/${_PACMAN_CHROOT}" pacman-key --populate archlinuxarm >/dev/null 2>&1
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}/${_PACMAN_CHROOT}"/etc/pacman.conf
# copy locale
echo "Copying locales to container ..."
cp "${_DIR}/usr/lib/locale/locale-archive" "${_DIR}/${_PACMAN_CHROOT}/usr/lib/locale/locale-archive"
# fix network in container
rm "${_DIR}/${_PACMAN_CHROOT}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${_DIR}/${_PACMAN_CHROOT}/etc/resolv.conf"
echo "Clean container, delete not needed files from ${_DIR}/${_PACMAN_CHROOT} ..."
rm -r "${_DIR}/${_PACMAN_CHROOT}"/usr/include
rm -r "${_DIR}/${_PACMAN_CHROOT}"/usr/share/{man,doc,info,locale}
echo "Generating tarball ..."
tar -acf ${_PACMAN_CHROOT}-latest.tar.zst -C "${_DIR}"/"${_PACMAN_CHROOT}" .
echo " Removing ${_DIR} ..."
rm -r "${_DIR}"
echo "Finished container tarball."

