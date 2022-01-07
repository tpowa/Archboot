#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR=""$1"/var/cache/pacman/pkg"
_CLEANUP_CACHE=""
_SAVE_RAM=""
_LINUX_FIRMWARE=""
_DIR=""
LATEST_ARM64="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
AARCH64_ARCHBOOT_FIRMWARE="/etc/archboot/archboot-linux-firmware-latest.tar.zst"

usage () {
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "This will create an archboot container for an archboot image."
	echo "Usage: ${_BASENAME} <directory> <options>"
	echo " Options:"
	echo "  -cc    Cleanup container eg. remove manpages, includes ..."
	echo "  -cp    Cleanup container package cache"
	exit 0
}

[[ -z "${1}" ]] && usage

_DIR="$1"

while [ $# -gt 0 ]; do
	case ${1} in
		-cc|--cc) _SAVE_RAM="1" ;;
		-cp|--cp) _CLEANUP_CACHE="1" ;;
        esac
	shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then
	echo "ERROR: Please run as root user!"
	exit 1
fi

# prepare pacman dirs
echo "Starting container creation ..."
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "Downloading archlinuxarm aarch64..."
    ! [[ -f ArchLinuxARM-aarch64-latest.tar.gz ]] && wget ${LATEST_ARM64}
fi
echo "Create directories in ${_DIR} ..."
mkdir "${_DIR}"
bsdtar -xf ArchLinuxARM-aarch64-latest.tar.gz -C "${_DIR}"
echo "Create locales in container ..."
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen" >/dev/null 2>&1
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen" >/dev/null 2>&1
systemd-nspawn -D "${_DIR}" locale-gen >/dev/null 2>&1
# generate pacman keyring
echo "Generate pacman keyring in container ..."
systemd-nspawn -D "${_DIR}" pacman-key --init >/dev/null 2>&1
systemd-nspawn -D "${_DIR}" pacman-key --populate archlinuxarm >/dev/null 2>&1
# disable checkspace option in pacman.conf, to allow to install packages in environment
sed -i -e 's:^CheckSpace:#CheckSpace:g' "${_DIR}"/etc/pacman.conf
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}"/etc/pacman.conf
# fix network in container
rm "${_DIR}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${_DIR}/etc/resolv.conf"
# update container to latest packages
echo "Update container to latest packages..."
systemd-nspawn -D "${_DIR}" pacman -Syu --noconfirm >/dev/null 2>&1
echo "Copy archboot-linux-firmware to container..."
cp "${AARCH64_ARCHBOOT_FIRMWARE}" "${_DIR}/"
# install archboot-arm
echo "Install archboot-arm and archboot-linux-firmware to container..."
systemd-nspawn -D "${_DIR}" /bin/bash -c "yes | pacman -U /archboot-linux-firmware-latest.tar.zst" >/dev/null 2>&1
systemd-nspawn -D "${_DIR}" pacman -S archboot-arm >/dev/null 2>&1
if [[ "${_SAVE_RAM}" ==  "1" ]]; then
    # clean container from not needed files
    echo "Clean container, delete not needed files from ${_DIR} ..."
    rm -r "${_DIR}"/usr/include
    rm -r "${_DIR}"/usr/share/{man,doc}
fi

if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
    # clean cache
    echo "Clean pacman cache from ${_DIR} ..."
    rm -r "${_DIR}"/var/cache/pacman
fi
echo "Finished container setup in ${_DIR} ."



# cleanup at the end
