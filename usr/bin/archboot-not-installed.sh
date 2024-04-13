#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_archboot_check
# consider only license or locale as uninstalled
rm -r /usr/share/{licenses,locale}
rm -r /usr/lib/{systemd,tmpfiles.d}
pacman -Sy
pacman -Q | cut -d ' ' -f1 >packages.txt
#shellcheck disable=SC2013
for i in $(cat packages.txt); do
    rm -r "${_PACMAN_LIB}"/local/"${i}"-*-[0-9]*
	#shellcheck disable=SC2086
    if pacman -Sdd ${i} --noconfirm >>log.txt; then
        echo "${i}" >> uninstalled.orig.txt
    else
		#shellcheck disable=SC2086
        pacman -Sdd ${i} --noconfirm --overwrite '*'
    fi
done
# remove false positives
grep -v -E "ca-certificates|dbus-broker-units|iana-etc|linux-firmware-marvell|linux-firmware-whence|pambase|pacman-mirrorlist|licenses" uninstalled.orig.txt >uninstalled.txt
# vim: set ft=sh ts=4 sw=4 et:
