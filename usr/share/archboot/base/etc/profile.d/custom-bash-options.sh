# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# check on bash
[[ -n "${BASH_VERSION:-}" ]] || return
# Not an interactive shell?
[[ $- == *i* ]] || return
if  [[ "${UID}" == 0 ]]; then
    # red for root user, host green, print full working dir
    PS1='[\e[1;31m\u\e[m@\e[1;32m\h\e[m \w]\$ '
else
    # blue for normal user,host green, print full working dir
    PS1='[\e[1;34m\u\e[m@\e[1;32m\h\e[m \w]\$ '
fi
# keep history clean from dups and spaces
HISTCONTROL="erasedups:ignorespace"
# color grep output
alias grep='grep --color=auto'
# if installed set  neovim as default editor
if command -v nvim >/dev/null; then
    alias vi='nvim'
    alias vim='nvim'
    alias edit='nvim'
fi
