#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Created by Tobias Powalowski <tpowa@archlinux.org>

# simulate login from tty on first screen session
if ! screen -ls &>/dev/null; then
    : > /.shell
    LOGIN=ssh
    clear
    echo -e "\e[1mLogin on $(tty) | $(uname -r) | $(date)\e[m"
    echo ""
    cat /etc/motd
    echo ""
    echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mscreen\e[m login or \e[1m\e[92mCTRL-C\e[m for \e[1mbash\e[m prompt.."
    read -r
fi
# define /bin/bash, else /bin/sh is the screen default
SHELL=/bin/bash screen -q -xRR
