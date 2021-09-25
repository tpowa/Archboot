#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR=""$1"/var/cache/pacman/pkg"
_FIRMWARE="linux-firmware"
_CLEANUP_CACHE=""
_MOVE_CACHE=""
_SAVE_RAM=""
_LINUX_FIRMWARE=""

usage () {
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "This will create an archboot container for an archboot image."
	echo "Usage: ${_BASENAME} <directory> <options>"
	echo " Options:"
	echo "  -c     Cleanup container eg. remove manpages, includes ..."
	echo "  -cp    Cleanup container package cache"
	echo "  -lf    add linux-firmware to container"
	echo "  -alf   add archboot-linux-firmware to container"
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 1 ]; do
	case ${2} in
		-cc|--cc) _SAVE_RAM="1" ;;
		-cp|--cp) _CLEANUP_CACHE="1" ;;
		-lf|--lf) _LINUX_FIRMWARE="linux-firmware" ;;
		-alf|-alf) _LINUX_FIRMWARE="archboot-linux-firmware" ;;
        esac
	shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi


# prepare pacman dirs
mkdir -p "$1"/var/lib/pacman
mkdir -p "${_CACHEDIR}"
# install archboot
pacman --root "$1" -Sy base archboot --noconfirm --cachedir "${_PWD}"/"${_CACHEDIR}"
# generate locales
systemd-nspawn -D "$1" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen"
systemd-nspawn -D "$1" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
systemd-nspawn -D "$1" locale-gen
# generate pacman keyring
systemd-nspawn -D "$1" pacman-key --init
systemd-nspawn -D "$1" pacman-key --populate archlinux
# add genneral mirror
systemd-nspawn -D "$1" /bin/bash -c "echo 'Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch' >> /etc/pacman.d/mirrorlist"
# disable checkspace option in pacman.conf, to allow to install packages in environment
systemd-nspawn -D "$1" /bin/bash -c "sed -i -e 's:^CheckSpace:#CheckSpace:g' /etc/pacman.conf"
# enable parallel downloads
systemd-nspawn -D "$1" /bin/bash -c "sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' /etc/pacman.conf"
# reinstall kernel to get files in /boot and firmware package
systemd-nspawn -D "$1" pacman -Sy linux --noconfirm
! [[ ${_LINUX_FIRMWARE} == "" ]] && systemd-nspawn -D "$1" pacman -Sy "${_LINUX_FIRMWARE}" --noconfirm

if [[ "${SAVE_RAM}" ==  "1" ]]; then
    # clean container from not needed files
    rm -r "$1"/usr/include
    rm -r "$1"/usr/share/{man,doc}
fi

if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
    # clean cache
    systemd-nspawn -D "$1" pacman -Scc --noconfirm
fi
