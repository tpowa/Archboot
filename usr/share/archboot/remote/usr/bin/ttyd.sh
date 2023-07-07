#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Created by Tobias Powalowski <tpowa@archlinux.org>

# simulate login from tty
if ! [[ -e /tmp/.setup-running ]]; then
    cat /etc/motd
    echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mshell\e[m login."
    read -r
fi
. /etc/profile
screen -q -R
