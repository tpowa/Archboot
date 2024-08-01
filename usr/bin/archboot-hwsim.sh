#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-hwsim.sh - setup a test SSID
# by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - HWSIM\e[m"
    echo -e "\e[1m----------------\e[m"
    echo "Create a simulated wireless SSID for testing purposes"
    echo "with mac80211_hwsim module."
    echo "- wlan0 will be setup as the AP. Don't use for scanning!"
    echo "- wlan1 will be setup for STATION mode. Use this for scanning for your AP."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <SSID>\e[m"
    exit 0
}
[[ -z "${1}" ]] && _usage
_archboot_check
echo "Waiting for pacman keyring..."
_pacman_keyring
echo "Installing kernel..."
pacman -Sydd --noconfirm --noscriptlet linux &>"${_LOG}"
depmod -a
if ! rg -qw 'mac80211_hwsim' /proc/modules; then
	modprobe mac80211_hwsim
fi
iwctl ap wlan0 stop
systemctl restart iwd
sleep 2
iwctl device wlan0 set-property Mode ap
iwctl device wlan0 set-property Powered on
iwctl ap wlan0 start "${1}" "12345678" && echo -e "\e[1mSSID:'${1}' with password '12345678' is online now.\e[m"
