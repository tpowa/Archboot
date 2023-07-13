#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.net"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Network Configuration"
_LOG="/dev/tty7"
_NO_LOG="/dev/null"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_net_interfaces() {
    find /sys/class/net/* -type l ! -name 'lo' -printf '%f ' -exec cat {}/address \;
}

_essid_scan() {
    # scan the area
    iwctl station "${_INTERFACE}" scan
    # only show lines with signal '*'
    # kill spaces from the end and replace spaces with + between
    # '+' character is one of 6 forbidden characters in SSID standard
    for dev in $(iwctl station "${_INTERFACE}" get-networks | grep '\*' | cut -c 1-41 | sed -e 's|\ *.$||g' -e 's|^.*\ \ ||g' -e 's| |\+|g'); do
        echo "${dev}"
        [[ "${1}" ]] && echo "${1}"
    done
}

_do_wireless() {
    _WLAN_HIDDEN=""
    _WLAN_SSID=""
    _WLAN_KEY=""
    _WLAN_AUTH=""
    if [[ "${_CONNECTION}" == "wireless" ]]; then
        # disconnect the interface first!
        iwctl station "${_INTERFACE}" disconnect &>"${_NO_LOG}"
        # clean old keys first!
        rm -f /var/lib/iwd/* &>"${_NO_LOG}"
        #shellcheck disable=SC2086,SC2046
        _dialog --menu "Choose your SSID:\n(Empty spaces in your SSID are replaced by '+' char)" 14 60 7 \
        $(_essid_scan _) \
            "Hidden" "_" 2>"${_ANSWER}" || return 1
        _WLAN_SSID=$(cat "${_ANSWER}")
        _WLAN_CONNECT="connect"
        if [[ "${_WLAN_SSID}" == "Hidden" ]]; then
            _dialog --inputbox "Enter the hidden SSID:" 8 65 \
                "secret" 2>"${_ANSWER}" || return 1
            _WLAN_SSID=$(cat "${_ANSWER}")
            _WLAN_CONNECT="connect-hidden"
            _WLAN_HIDDEN=1
        fi
        # replace # with spaces again
        #shellcheck disable=SC2001,SC2086
        _WLAN_SSID="$(echo ${_WLAN_SSID} | sed -e 's|\+|\ |g')"
        #shellcheck disable=SC2001,SC2086
        while [[ -z "${_WLAN_AUTH}" ]]; do
            # expect hidden network has a WLAN_KEY
            #shellcheck disable=SC2143
            if ! [[ "$(iwctl station "${_INTERFACE}" get-networks | grep -w "${_WLAN_SSID}" | cut -c 42-49 | grep -q 'open')" ]] || [[ "${_WLAN_CONNECT}" == "connect-hidden" ]]; then
                _dialog --inputbox "Enter your KEY for SSID='${_WLAN_SSID}'" 8 50 "SecretWirelessKey" 2>"${_ANSWER}" || return 1
                _WLAN_KEY=$(cat "${_ANSWER}")
            fi
            # time to connect
            _dialog --infobox "Connection to SSID='${_WLAN_SSID}' with interface ${_INTERFACE}..." 3 70
            _printk off
            if [[ -z "${_WLAN_KEY}" ]]; then
                iwctl station "${_INTERFACE}" "${_WLAN_CONNECT}" "${_WLAN_SSID}" &>"${_NO_LOG}" && _WLAN_AUTH=1
            else
                iwctl --passphrase="${_WLAN_KEY}" station "${_INTERFACE}" "${_WLAN_CONNECT}" "${_WLAN_SSID}" &>"${_NO_LOG}" && _WLAN_AUTH=1
            fi
            if [[ -n "${_WLAN_AUTH}" ]]; then
                _dialog --infobox "Authentification was successful. Continuing in 5 seconds..." 3 70
                sleep 5
            else
                _dialog --msgbox "Error:\nAuthentification failed. Please configure again!" 6 60
            fi
            _printk on
        done
    fi
}

_donetwork() {
    _S_NET=""
    _NETPARAMETERS=""
    while [[ -z "${_NETPARAMETERS}" ]]; do
        # select network interface
        _INTERFACE=""
        _INTERFACES=$(_net_interfaces)
        while [[ -z "${_INTERFACE}" ]]; do
            #shellcheck disable=SC2086
            _dialog --ok-label "Select" --menu "Select a network interface:" 12 40 6 ${_INTERFACES} 2>"${_ANSWER}"
            case $? in
                1) return 1 ;;
                0) _INTERFACE=$(cat "${_ANSWER}") ;;
            esac
        done
        echo "${_INTERFACE}" >/tmp/.network-interface
        # iwd renames wireless devices to wlanX
        if echo "${_INTERFACE}" | grep -q wlan; then
            _CONNECTION="wireless"
        else
            _CONNECTION="ethernet"
        fi
        # profile name
        _NETWORK_PROFILE=""
        _dialog --inputbox "Enter your network profile name:" 7 40 "${_INTERFACE}-${_CONNECTION}" 2>"${_ANSWER}" || return 1
        _NETWORK_PROFILE=/etc/systemd/network/$(cat "${_ANSWER}").network
        # wifi setup first
        _do_wireless || return 1
        # dhcp switch
        _IP=""
        _dialog --yesno "Do you want to use DHCP?" 5 40
        #shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            _IP="dhcp"
            _IPADDR=""
            _GW=""
            _DNS=""
        else
            _IP="static"
            _dialog --inputbox "Enter your IP address and netmask:" 8 40 "192.168.1.23/24" 2>"${_ANSWER}" || return 1
            _IPADDR=$(cat "${_ANSWER}")
            _dialog --inputbox "Enter your gateway:" 8 40 "192.168.1.1" 2>"${_ANSWER}" || return 1
            _GW=$(cat "${_ANSWER}")
            _dialog --inputbox "Enter your DNS server IP:" 8 40 "192.168.1.1" 2>"${_ANSWER}" || return 1
            _DNS=$(cat "${_ANSWER}")
        fi
            # http/ftp proxy settings
        _dialog --inputbox "Enter your proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 13 65 "" 2>"${_ANSWER}" || return 1
        _PROXY=$(cat "${_ANSWER}")
        _PROXIES="http_proxy https_proxy ftp_proxy rsync_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY"
        _dialog --yesno "Are these settings correct?\n\nInterface:    ${_INTERFACE}\nConnection:   ${_CONNECTION}\nNetwork profile: ${_NETWORK_PROFILE}\nSSID:      ${_WLAN_SSID}\nHidden:     ${_WLAN_HIDDEN}\nKey:        ${_WLAN_KEY}\ndhcp or static: ${_IP}\nIP address: ${_IPADDR}\nGateway:    ${_GW}\nDNS server: ${_DNS}\nProxy setting: ${_PROXY}" 0 0
        case $? in
            1) ;;
            0) _NETPARAMETERS=1 ;;
        esac
    done
    # write systemd-networkd profile
    echo "#$_NETWORK_PROFILE generated by archboot setup" > "${_NETWORK_PROFILE}"
    #shellcheck disable=SC2129
    echo "[Match]"  >> "${_NETWORK_PROFILE}"
    echo "Name=${_INTERFACE}" >> "${_NETWORK_PROFILE}"
    echo "" >> "${_NETWORK_PROFILE}"
    echo "[Network]" >> "${_NETWORK_PROFILE}"
    [[ "${_IP}" == "dhcp" ]] && echo "DHCP=yes" >> "${_NETWORK_PROFILE}"
    if [[ "${_CONNECTION}" == "wireless" ]]; then
        #shellcheck disable=SC2129
        echo "IgnoreCarrierLoss=3s" >>"${_NETWORK_PROFILE}"
    fi
    if [[ "${_IP}" == "static" ]]; then
        #shellcheck disable=SC2129
        echo "Address=${_IPADDR}" >>"${_NETWORK_PROFILE}"
        echo "Gateway=${_GW}" >>"${_NETWORK_PROFILE}"
        echo "DNS=${_DNS}" >>"${_NETWORK_PROFILE}"
    fi
    # set proxies
    if [[ -z "${_PROXY}" ]]; then
        for i in ${_PROXIES}; do
            unset "${i}"
        done
    else
        for i in ${_PROXIES}; do
            export "${i}"="${_PROXY}"
        done
    fi
    if [[ -e /etc/systemd/network/10-wired-auto-dhcp.network ]]; then
        echo "Disabled Archboot's bootup wired auto dhcp browsing." >"${_LOG}"
        rm /etc/systemd/network/10-wired-auto-dhcp.network
    fi
    echo "Using setup's network profile ${_NETWORK_PROFILE} now..." >"${_LOG}"
    systemctl restart systemd-networkd
    systemctl restart systemd-resolved
    _dialog --infobox "Waiting for network link to come up..." 3 60
    # add sleep here for systemd-resolve get correct values
    sleep 5
    if ! getent hosts www.google.com &>"${_LOG}"; then
        _dialog --msgbox "Error:\nYour network is not working correctly, please configure again!" 6 70
        return 1
    fi
    _dialog --infobox "Link is up. Continuing in 5 seconds..." 3 60
    sleep 5
}

if [[ -e /tmp/.net-running ]]; then
    clear
    echo "net already runs on a different console!"
    echo "Please remove /tmp/.net-running first to launch net!"
    exit 1
fi
: >/tmp/.net-running
if ! _donetwork; then
    clear
    [[ -e /tmp/.net ]] && rm /tmp/.net
    [[ -e /tmp/.net-running ]] && rm /tmp/.net-running
    exit 1
fi
[[ -e /tmp/.net ]] && rm /tmp/.net
[[ -e /tmp/.net-running ]] && rm /tmp/.net-running
clear
exit 0
# vim: set ft=sh ts=4 sw=4 et: