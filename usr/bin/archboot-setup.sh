#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# source base and common first, contains basic parameters
. /usr/lib/archboot/installer/common.sh
. /usr/lib/archboot/installer/base.sh
# source all other functions
. /usr/lib/archboot/installer/autoconfiguration.sh
. /usr/lib/archboot/installer/autoprepare.sh
. /usr/lib/archboot/installer/blockdevices.sh
. /usr/lib/archboot/installer/bootloader.sh
. /usr/lib/archboot/installer/btrfs.sh
. /usr/lib/archboot/installer/configuration.sh
. /usr/lib/archboot/installer/mountpoints.sh
. /usr/lib/archboot/installer/network.sh
. /usr/lib/archboot/installer/pacman.sh
. /usr/lib/archboot/installer/partition.sh
. /usr/lib/archboot/installer/storage.sh
if [[ -e /tmp/.setup-running ]]; then
    _dialog --msgbox "Attention:\n\nSetup already runs on a different console!\nPlease remove /tmp/.setup-running first to launch setup!" 8 60
    exit 1
fi
: >/tmp/.setup-running
: >/tmp/.setup
_set_title
_set_uefi_parameters
while true; do
    _mainmenu
done
clear
exit 0
# vim: set ts=4 sw=4 et:
