#!/usr/bin/env bash
#
#    archboot-hwsim.sh - setup a test SSID
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")

usage()
{
    echo -e "\033[1mWelcome to \033[34marchboot's\033[0m \033[1mHWSIM:\033[0m"
    echo -e "\033[1m---------------------------------------\033[0m"
    echo "Create a simulated wireless SSID for testing purposes with mac80211_hwsim module."
	echo "- wlan0 will be the AP"
	echo "- wlan1 will be for STATION mode"
    echo -e "usage: \033[1m${APPNAME} <SSID>\033[0m"
    exit "1"
}

if [ $# -gt 0 ]; then
    usage
fi

if ! grep -qw mac80211_hwsim /proc/modules; then
	modprobe mac80211_hwsim
fi
iwctl ap wlan0 stop
systemctl restart iwd
sleep 2
iwctl device wlan0 set-property Mode ap
iwctl device wlan0 set-property Powered on
iwctl ap wlan0 start "$1" "12345678"
