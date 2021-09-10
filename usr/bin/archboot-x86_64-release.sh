#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
usage () {
	echo "${_BASENAME}:"
	echo "CREATE ARCHBOOT RELEASE IMAGE"
	echo "-----------------------------"
	echo "Usage: ${_BASENAME} <directory>"
	echo "This will create an archboot release image in <directory>."
	exit 0
}

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi
mkdir -p $1
cd $1
archboot-create-container.sh archboot-release
systemd-nspawn -D archboot-release archboot-x86_64-iso.sh -t -i=archrelease
systemd-nspawn -D archboot-release archboot-x86_64-iso.sh -g -T=archrelease.tar
mv archboot-release/*.iso ./

