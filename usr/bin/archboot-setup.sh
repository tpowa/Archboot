#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# source base and common first, contains basic parameters
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/installer/common.sh
. /usr/lib/archboot/installer/base.sh
# source all other functions
. /usr/lib/archboot/installer/autoconfiguration.sh
. /usr/lib/archboot/installer/quicksetup.sh
. /usr/lib/archboot/installer/blockdevices.sh
. /usr/lib/archboot/installer/bootloader.sh
. /usr/lib/archboot/installer/bootloader_grub.sh
. /usr/lib/archboot/installer/bootloader_limine.sh
. /usr/lib/archboot/installer/bootloader_sb.sh
. /usr/lib/archboot/installer/bootloader_systemd_bootd.sh
. /usr/lib/archboot/installer/bootloader_refind.sh
. /usr/lib/archboot/installer/bootloader_uboot.sh
. /usr/lib/archboot/installer/bootloader_uki.sh
. /usr/lib/archboot/installer/bootloader_pacman_hooks.sh
. /usr/lib/archboot/installer/btrfs.sh
. /usr/lib/archboot/installer/configuration.sh
. /usr/lib/archboot/installer/mountpoints.sh
. /usr/lib/archboot/installer/pacman.sh
. /usr/lib/archboot/installer/partition.sh
. /usr/lib/archboot/installer/storage.sh
if [[ -e /tmp/.setup-running ]]; then
    _dialog --msgbox "Attention:\n\nSetup already runs on a different console!\nPlease remove /tmp/.setup-running first to launch setup!" 8 60
    exit 1
fi
_set_title
if ! [[ "${UID}" == 0 ]]; then
    _dialog --msgbox "Error:\n\nSetup needs to run as root user." 7 40
    reset
    exit 1
fi
: >/tmp/.setup-running
: >/tmp/.setup
_set_uefi_parameters
while true; do
    _mainmenu
done
reset
exit 0
