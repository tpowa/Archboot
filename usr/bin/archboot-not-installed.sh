#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_archboot_check
# consider only license package and locale as uninstalled
# it's hard to track manually changes in systemd files
# added those directories with _full_dir
rm -r /usr/share/{licenses,locale} /usr/lib/{systemd,tmpfiles.d}
pacman -Sy
#shellcheck disable=SC2013
for i in $(pacman -Q | cut -d ' ' -f1); do
    rm -r "${_PACMAN_LIB}"/local/$(pacman -Q ${i} | cut -d ' ' -f1,2 | sed -s 's# #-#g')
    #shellcheck disable=SC2086
    if pacman -Sdd ${i} --noconfirm >>log.txt; then
        echo "${i}" >> not-installed.orig.txt
    else
        #shellcheck disable=SC2086
        pacman -Sdd ${i} --noconfirm --overwrite '*'
    fi
done
# remove false positives:
# ca-certificates has no files
# dbus-broker-units only systemd files
# iana-etc only /etc files
# licenses mandatory removed
# linux-firmware-whence only license files
# pacman-mirrorlist only /etc file
# pambase only /etc files
rg -v "ca-certificates|dbus-broker-units|iana-etc|licenses|linux-firmware-whence|pacman-mirrorlist|pambase" not-installed.orig.txt >not-installed.txt
# vim: set ft=sh ts=4 sw=4 et:
