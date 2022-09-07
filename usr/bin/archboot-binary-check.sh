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
    exit 0
}

[[ -z "${1}" ]] && usage

if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi

# update pacman db first
pacman -Sy
if [[ "${1}" == "base" ]]; then
    PACKAGE="$(pacman -Qi base | grep Depends | cut -d ":" -f2)"
else
    PACKAGE="${1}"
fi
echo "${PACKAGE}" >binary.txt
#shellcheck disable=SC2086
for i in $(pacman -Ql ${PACKAGE} | grep "/usr/bin/..*"$ | cut -d' ' -f2); do
	which "${i}" >/dev/null || echo "${i}">>binary.txt
done
