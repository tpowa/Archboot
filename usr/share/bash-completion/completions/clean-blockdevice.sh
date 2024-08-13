# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_clean_blockdevice()
{
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    compopt -o bashdefault -o default
    COMPREPLY=( $(compgen -W "$(lsblk -pnro NAME,TYPE | rg '(.*) disk$' -r '$1')" -- $cur) )
    return 0
}
complete -F _clean_blockdevice clean-blockdevice.sh
