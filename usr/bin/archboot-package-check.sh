#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Check On Not Installed Packages\e[m"
    echo "-------------------------------------------"
    echo "This will check on packages, which don't have any files in the environment"
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}
[[ -z "${1}" ]] && _usage
_archboot_check
cd /var/lib/pacman/local
:>/pkg-found.txt
for i in $(fd -t f files); do
    for k in $(bat "${i}" | rg -v '/$'); do
        [[ -e /"${k}" ]] && echo "${i}" | sd '/files$' '' >>/pkg-found.txt
    done
done
sort -u /pkg-found.txt > /pkg-uniq.txt
rm /pkg-found.txt
pacman -Q >/pkg-install.txt
sd ' ' '-' /pkg-install.txt
diff -u /pkg-uniq.txt /pkg-install.txt | rg '\\+' > /pkg-not-installed.txt
rm /pkg-uniq.txt /pkg-install.txt
