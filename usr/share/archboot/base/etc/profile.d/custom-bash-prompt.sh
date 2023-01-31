# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# check on bash
[[ -n "${BASH_VERSION:-}" ]] || return
if  [[ "${UID}" == 0 ]]; then
    PS1='[\e[1;31m\u\e[m@\e[1;32m\h\e[m \W]\$ '
else
    PS1='[\e[1;34m\u\e[m@\e[1;32m\h\e[m \W]\$ '
fi

