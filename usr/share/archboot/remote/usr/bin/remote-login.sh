#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Created by Tobias Powalowski <tpowa@archlinux.org>

# simulate login from tty on first screen session
if ! screen -ls &>/dev/null; then
    [[ -z "${SSH_TTY}" ]] && cat /etc/motd
    echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mshell\e[m login."
    read -r
fi
# define /bin/bash, else /bin/sh is the screen default
SHELL=/bin/bash screen -q -xRR
