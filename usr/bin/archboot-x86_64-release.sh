#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE ARCHBOOT RELEASE IMAGE"
	echo "-----------------------------"
	echo "Usage: ${_BASENAME} <directory>"
	echo "This will create an archboot release image."
	exit 0
}
while [ $# -gt 0 ]; do
	case ${1} in
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi
mkdir -p $1
cd $1
archboot-x86_64-release.sh archboot-release
systemd-nspawn -D $1 archboot-x86_64-iso.sh -t
systemd-nspawn -D $1 archboot-x86_64-iso.sh -g -T=*.tar
mv $1/*.iso ../

