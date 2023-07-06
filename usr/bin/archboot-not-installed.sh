#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi
rm -r /usr/share/licenses
pacman -Sy
pacman -Q | cut -d ' ' -f1 >packages.txt
for i in $(cat packages.txt); do
    rm -r /var/lib/pacman/local/${i}*
	#shellcheck disable=SC2086
    if pacman -S ${i} --noconfirm &>>log.txt; then
        echo "${i}" >> uninstalled.orig.txt
    else
		#shellcheck disable=SC2086
        pacman -S ${i} --noconfirm --overwrite '*'
    fi
done
# remove false positives
grep -v "linux-firmware-marvell pambase pacman-mirrorlist licenses" uninstalled.orig.txt >uninstalled.txt
# vim: set ft=sh ts=4 sw=4 et:
