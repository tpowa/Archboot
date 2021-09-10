#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "Usage: ${_BASENAME} <directory>"
	echo "This will create an archboot container for an archboot image."
	exit 0
}

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi
mkdir -p $1/var/lib/pacman
pacman --root "$1" -Sy base archboot --noconfirm
systemd-nspawn -D $1 /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen"
systemd-nspawn -D $1 /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
systemd-nspawn -D $1 locale-gen
systemd-nspawn -D $1 pacman-key --init
systemd-nspawn -D $1 pacman-key --populate archlinux
systemd-nspawn -D $1 /bin/bash -c "echo 'Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch' >> /etc/pacman.d/mirrorlist"
systemd-nspawn -D $1 pacman -Sy linux --noconfirm
