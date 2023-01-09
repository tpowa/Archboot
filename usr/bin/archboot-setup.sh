#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# source base and common first, contains basic parameters
. /usr/lib/archboot/installer/base.sh
. /usr/lib/archboot/installer/common.sh
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
_dialog --msgbox "Welcome to the Archboot Arch Linux Installation program.\n\nThe install process is fairly straightforward, and you should run through the options in the order they are presented.\n\nIf you are unfamiliar with partitioning/making filesystems, you may want to consult some documentation before continuing.\n\nYou can view all output from commands by viewing your ${_VC} console (ALT-F${_VC_NUM}). ALT-F1 will bring you back here." 14 65
while true; do
    _mainmenu
done
clear
exit 0
# vim: set ts=4 sw=4 et:
