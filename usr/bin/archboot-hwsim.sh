#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#    archboot-hwsim.sh - setup a test SSID
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
_APPNAME=$(basename "${0}")
_usage()
{
    echo -e "\e[1mWelcome to \e[34marchboot's\e[0m \e[1mHWSIM:\e[0m"
    echo -e "\e[1m---------------------------------------\e[0m"
    echo "Create a simulated wireless SSID for testing purposes"
    echo "with mac80211_hwsim module."
	echo "- wlan0 will be setup as the AP. Don't use for scanning!"
	echo "- wlan1 will be setup for STATION mode. Use this for scanning for your AP."
    echo -e "usage: \e[1m${_APPNAME} <SSID>\e[0m"
    exit 0
}
[[ -z "${1}" ]] && _usage
if ! grep -qw mac80211_hwsim /proc/modules; then
	modprobe mac80211_hwsim
fi
iwctl ap wlan0 stop
systemctl restart iwd
sleep 2
iwctl device wlan0 set-property Mode ap
iwctl device wlan0 set-property Powered on
iwctl ap wlan0 start "${1}" "12345678" && echo -e "\e[1mSSID:'${1}' with password '12345678' is online now.\e[0m"
