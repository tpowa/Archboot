# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_restore_usbstick()
{
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    compopt -o bashdefault -o default
    COMPREPLY=( $(compgen -W "$(lsblk -pnro NAME,TRAN,TYPE | rg '(.*) disk$' -r '$1' | rg (.*) usb$' -r '$1')" -- $cur) )
    return 0
}
complete -F _restore_usbstick restore-usbstick.sh
