# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# check on bash
[[ -n "${BASH_VERSION:-}" ]] || return
# Not an interactive shell?
[[ $- == *i* ]] || return
# keep history clean from dups and spaces
HISTCONTROL="erasedups:ignorespace"

