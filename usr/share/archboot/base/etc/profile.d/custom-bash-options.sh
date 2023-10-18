# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# check on bash
[[ -n "${BASH_VERSION:-}" ]] || return
# Not an interactive shell?
[[ $- == *i* ]] || return
if [[ "${UID}" == 0 ]]; then
    # red for root user, host green, print full working dir
    PS1='[\[\e[1;31m\]\u\[\e[m\]@\[\e[1;32m\]\h\[\e[m\] \e[1m\w\e[m]\$ '
else
    # blue for normal user,host green, print full working dir
    PS1='[\[\e[1;34m\]\u\[\e[m\]@\[\e[1;32m\]\h\[\e[m\] \e[1m\w\e[m]]\$ '
fi
# color man pages
export GROFF_NO_SGR=1
# keep history clean from dups and spaces
HISTCONTROL="erasedups:ignorespace"
# if installed set neovim as default editor
if command -v nvim >/dev/null; then
    alias vi='nvim'
    alias vim='nvim'
    alias edit='nvim'
fi
# show MOTD on ttyd login
if [[ -z "${TTY}" && -z "${SSH_TTY}" && -z "${TMUX}" && "$(grep -w 'archboot' /etc/hostname)" ]]; then
    [[ "${SHLVL}" == "2" ]] && cat /etc/motd
fi
# run remote-login.sh on ssh connection
if [[ -z "${STY}" && -n "${SSH_TTY}" && "$(grep -w 'archboot' /etc/hostname)" ]]; then
    /usr/bin/remote-login.sh
    exit 0
fi
