#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_APPNAME=${0##*/}
_usage () {
    echo "Check on missing binaries in archboot environment"
    echo "-------------------------------------------------"
    echo "This will check binaries from package, if they exist"
    echo "and report missing to binary.txt"
    echo ""
    echo "usage: ${_APPNAME} <package>"
    exit 0
}
[[ -z "${1}" ]] && _usage
_archboot_check
# update pacman db first
pacman --noconfirm -Sy
if [[ "${1}" == "base" ]]; then
    pacman --noconfirm -S base
    _PACKAGE="$(LANG=C.UTF-8 pacman -Qi base | rg -o 'Depends.*: (.*)' -r '$1')"
else
    _PACKAGE="${1}"
fi
echo "${_PACKAGE}" >binary.txt
#shellcheck disable=SC2086
for i in $(pacman -Ql ${_PACKAGE} | rg -o '/usr/bin/..*$'); do
	command -v "${i}" &>"${_NO_LOG}" || echo "${i}" >>binary.txt
done
# vim: set ft=sh ts=4 sw=4 et:
