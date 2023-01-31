# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# check on bash
[[ -n "${BASH_VERSION:-}" ]] || return
# color output
alias ls='ls --color=auto'
alias grep='grep --color=auto'
# set neovim as default editor
alias vi='nvim'
alias vim='nvim'
alias edit='nvim'

