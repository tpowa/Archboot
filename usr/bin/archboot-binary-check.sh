#!/bin/bash
#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"

usage () {
    echo "${_BASENAME}: usage"
    echo "Check on missing binaries in archboot environment"
    echo "-------------------------------------------------"
    echo "Usage: ${_BASENAME} <package>" 
    echo "This will check binaries from package, if they exist"
    echo "and report missing to binary.txt"
    echo ""
    echo "  -h This message."
    exit 0
}

[[ -z "${1}" ]] && usage

if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi

while [ $# -gt 0 ]; do
    case ${1} in
        -h|--h|?) usage; exit 0 ;;
        esac
    shift
done

echo $1 >binary.txt
for i in $(pacman -Ql $1 | grep "/usr/bin/..*");do
	which $i >/dev/null || echo $i>>binary.txt 
done
