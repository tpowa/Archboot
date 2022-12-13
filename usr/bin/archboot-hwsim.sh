#!/bin/bash
if ! grep -qw mac80211_hwsim /proc/modules; then
	modprobe mac80211_hwsim
fi
iwctl ap wlan0 stop
iwctl restart iwd
iwctl device wlan0 set-property Mode ap
iwctl device wlan0 set-property Powered on
iwctl ap wlan0 start "$1" "12345678"
