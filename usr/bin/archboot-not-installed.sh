#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Check Not Installed Packages\e[m"
    echo -e "\e[1m---------------------------------------\e[m"
    echo "Check the system for uninstalled packages with pacman."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_archboot_check
# consider only license package and locale as uninstalled
# it's hard to track manually changes in systemd files
# added those directories with _full_dir
rm -r /usr/share/{licenses,locale} /usr/lib/{systemd,tmpfiles.d}
pacman -Sy
#shellcheck disable=SC2013
for i in $(pacman -Q | choose 0); do
    #shellcheck disable=SC2086
    rm -r "${_PACMAN_LIB}"/local/"$(pacman -Q ${i} | sd ' ' '-')"
    #shellcheck disable=SC2086
    if pacman -Sdd ${i} --noconfirm >>pacman.log; then
        echo "${i}" >> not-installed.orig.log
    else
        #shellcheck disable=SC2086
        pacman -Sdd ${i} --noconfirm --overwrite '*'
    fi
done
# remove false positives:
# ca-certificates has no files
# dbus-broker-units only systemd files
# gnulib-l10n only files in /usr/share/locale
# iana-etc only /etc files
# licenses mandatory removed
# linux-firmware-whence only license files
# linux-firmware-marvell is available on marvell systems
# pacman-mirrorlist only /etc file
# pambase only /etc files
rg -v "ca-certificates|dbus-units|dbus-broker-units|gnulib-l10n|iana-etc|licenses|linux-firmware-whence|linux-firmware-marvell||pacman-mirrorlist|pambase" not-installed.orig.log >not-installed.log
