#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Network Configuration"

_printk()
{
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}

_online_switch() {
    if _dialog --title " Offline Mode " --defaultno --yesno "Do you want to switch to Online Mode?" 5 45; then
        rm /var/cache/pacman/pkg/archboot.db
    else
        _cleanup
    fi
}

_net_interfaces() {
    #shellcheck disable=SC2016
    fd -E '/lo' . '/sys/class/net' -x rg '(.*)' -r '{/} $1' {}/address | sort -u
}

_essid_scan() {
    iwctl station "${_INTERFACE}" scan &>"${_NO_LOG}"
    _COUNT=0
    while true; do
        sleep 1
        _COUNT=$((_COUNT+1))
        # abort after 5 seconds
        _progress "$((_COUNT*20))" "Scanning $((5-_COUNT)) second(s) for SSIDs with interface ${_INTERFACE}..."
        [[ "${_COUNT}" == 5 ]] && break
    done
}

_wireless() {
    _WLAN_HIDDEN=""
    _WLAN_SSID=""
    _WLAN_KEY=""
    _WLAN_AUTH=""
    # unblock all interfaces!
    rfkill unblock all
    # disconnect the interface first!
    iwctl station "${_INTERFACE}" disconnect &>"${_NO_LOG}"
    # clean old keys first!
    rm -f /var/lib/iwd/* &>"${_NO_LOG}"
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        # scan the area
        _essid_scan | _dialog --title " Network Configuration " --no-mouse --gauge "Scanning 5 second(s) for SSIDs with interface ${_INTERFACE}..." 6 60
        # only show lines with signal '*'
        # kill spaces from the end and replace spaces with + between
        #shellcheck disable=SC2086,SC2046
        if _dialog --cancel-label "${_LABEL}" --title " SSID Scan Result " --menu "Empty spaces in your SSID are replaced by '+' char" 13 60 6 \
            "RESCAN" "SSIDs" "HIDDEN" "SSID" $(iwctl station "${_INTERFACE}" get-networks |\
            rg -o ' {6}(.{34}).*\*' -r '$1' |\
            sd ' ' '+' | sd '\++$' ' _') 2>"${_ANSWER}"; then
            _WLAN_SSID=$(cat "${_ANSWER}")
            _CONTINUE=1
            if rg -q 'RESCAN' "${_ANSWER}"; then
                _dialog --title " Intel Wireless Daemon " --no-mouse --infobox "Restarting IWD Daemon..." 3 50
                systemctl restart iwd
                _CONTINUE=""
            fi
        else
            _abort
        fi
    done
    _WLAN_CONNECT="connect"
    if [[ "${_WLAN_SSID}" == "HIDDEN" ]]; then
        _dialog --no-cancel --title " HIDDEN SSID " --inputbox "" 7 65 "secret" 2>"${_ANSWER}"
        _WLAN_SSID=$(cat "${_ANSWER}")
        _WLAN_CONNECT="connect-hidden"
        _WLAN_HIDDEN=1
    fi
    # replace # with spaces again
    #shellcheck disable=SC2001,SC2086
    _WLAN_SSID="$(echo ${_WLAN_SSID} | sd '\+' ' ')"
    # expect hidden network has a WLAN_KEY
    #shellcheck disable=SC2143
    if ! [[ "$(iwctl station "${_INTERFACE}" get-networks | rg -q "${_WLAN_SSID}.*open")" ]] \
    || [[ "${_WLAN_CONNECT}" == "connect-hidden" ]]; then
        _dialog --no-cancel --title " Connection Key " --inputbox "" 7 50 "Secret-WirelessKey" 2>"${_ANSWER}"
        _WLAN_KEY=$(cat "${_ANSWER}")
    fi
    # time to connect
    _dialog --title " Network Configuration " --no-mouse --infobox "Connecting to '${_WLAN_SSID}'\nwith interface ${_INTERFACE}..." 4 50
    _printk off
    if [[ -z "${_WLAN_KEY}" ]]; then
        echo "" | iwctl station "${_INTERFACE}" "${_WLAN_CONNECT}" "${_WLAN_SSID}" &>"${_NO_LOG}" && _WLAN_AUTH=1
    else
        iwctl --passphrase="${_WLAN_KEY}" station "${_INTERFACE}" "${_WLAN_CONNECT}" "${_WLAN_SSID}" &>"${_NO_LOG}" && _WLAN_AUTH=1
    fi
    sleep 3
    _printk on
    if [[ -n "${_WLAN_AUTH}" ]]; then
        _dialog --title " Success " --no-mouse --infobox "Authentification to '${_WLAN_SSID}' was successful." 3 70
        sleep 2
        return 0
    else
        _dialog --title " ERROR " --no-mouse --infobox "Authentification to ${_WLAN_SSID}' failed.\nPlease configure again!" 4 70
        sleep 5
        return 1
    fi
}

_network() {
    if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        _online_switch
    fi
    _NETPARAMETERS=""
    while [[ -z "${_NETPARAMETERS}" ]]; do
        # select network interface
        _INTERFACE=""
        _INTERFACES=$(_net_interfaces)
        while [[ -z "${_INTERFACE}" ]]; do
            #shellcheck disable=SC2086
            if _dialog --cancel-label "${_LABEL}" --title " Network Interface " --menu "" 11 40 5 ${_INTERFACES} 2>"${_ANSWER}"; then
                _INTERFACE=$(cat "${_ANSWER}")
            else
                _abort
            fi
        done
        echo "${_INTERFACE}" >/.network-interface
        # iwd renames wireless devices to wlanX
        if echo "${_INTERFACE}" | rg -q 'wlan'; then
            _CONNECTION="wireless"
        else
            _CONNECTION="ethernet"
        fi
        # profile name
        _NETWORK_PROFILE=""
        _dialog --no-cancel --title " Network Profile Name " --inputbox "" 7 40 "${_INTERFACE}-${_CONNECTION}" 2>"${_ANSWER}"
        _NETWORK_PROFILE=/etc/systemd/network/$(cat "${_ANSWER}").network
        # wifi setup first
        _CONTINUE=""
        while [[ -z "${_CONTINUE}" && "${_CONNECTION}" == "wireless" ]]; do
            if _wireless; then
                _CONTINUE=1
            else
                _CONTINUE=""
            fi
        done
        # dhcp switch
        _IP=""
        if _dialog --title " Network Configuration " --yesno "Do you want to use DHCP?" 5 40; then
            _IP="dhcp"
            _IPADDR=""
            _GW=""
            _DNS=""
        else
            _IP="static"
            while true; do
                _dialog  --no-cancel --title " IP Address And Netmask " --inputbox "" 7 40 "192.168.1.23/24" 2>"${_ANSWER}"
                _IPADDR=$(cat "${_ANSWER}")
                if echo ${_IPADDR} | rg -q '/'; then
                    break
                else
                    _dialog --title " ERROR " --no-mouse --infobox "No netmask was given, please add netmask too eg. /24!" 3 60
                    sleep 3
                fi
            done
            _dialog --no-cancel --title " Gateway " --inputbox "" 7 40 "$(echo ${_IPADDR} | choose 0 1 2 -f '\.' -o '.').1" 2>"${_ANSWER}"
            _GW=$(cat "${_ANSWER}")
            _dialog --no-cancel --title " Domain Name Server " --inputbox "" 7 40 "${_GW}" 2>"${_ANSWER}"
            _DNS=$(cat "${_ANSWER}")
        fi
        # http/ftp proxy settings
        _dialog --no-cancel --title " Proxy Server " --inputbox "\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 13 65 "" 2>"${_ANSWER}"
        _PROXY=$(cat "${_ANSWER}")
        _PROXIES="http_proxy https_proxy ftp_proxy rsync_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY"
        _dialog --title " Summary " --yesno "Interface:    ${_INTERFACE}\nConnection:   ${_CONNECTION}\nNetwork profile: ${_NETWORK_PROFILE}\nSSID:      ${_WLAN_SSID}\nHidden:     ${_WLAN_HIDDEN}\nKey:        ${_WLAN_KEY}\ndhcp or static: ${_IP}\nIP address: ${_IPADDR}\nGateway:    ${_GW}\nDNS server: ${_DNS}\nProxy setting: ${_PROXY}" 0 0 && _NETPARAMETERS=1
    done
    # write systemd-networkd profile
    echo "#$_NETWORK_PROFILE generated by Archboot setup" > "${_NETWORK_PROFILE}"
    #shellcheck disable=SC2129
    echo "[Match]"  >> "${_NETWORK_PROFILE}"
    echo "Name=${_INTERFACE}" >> "${_NETWORK_PROFILE}"
    echo "" >> "${_NETWORK_PROFILE}"
    echo "[Network]" >> "${_NETWORK_PROFILE}"
    echo "MulticastDNS=yes" >> "${_NETWORK_PROFILE}"
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
            echo "export ${i}=${_PROXY}" >> /etc/profile.d/proxy.sh
            chmod a+x "${_DESTDIR}"/etc/profile.d/proxy.sh
        done
    fi
    if [[ -e /etc/systemd/network/10-wired-auto-dhcp.network ]]; then
        echo "Disabled Archboot's bootup wired auto dhcp browsing." >"${_LOG}"
        rm /etc/systemd/network/10-wired-auto-dhcp.network
    fi
    echo "Using setup's network profile ${_NETWORK_PROFILE} now..." >"${_LOG}"
    systemctl restart systemd-networkd
    systemctl restart systemd-resolved
    # add sleep here for systemd-resolve get correct values
    _COUNT=0
    while true; do
        sleep 1
        if getent hosts www.google.com &>"${_LOG}"; then
            _progress "100" "Network configuration completed successfully."
            sleep 2
            return 0
        fi
        _COUNT=$((_COUNT+1))
        # abort after 10 seconds
        _progress "$((_COUNT*10))" "Waiting $((10-_COUNT)) seconds for network link to come up..."
        [[ "${_COUNT}" == 10 ]] && break
    done | _dialog --title " Network Configuration " --no-mouse --gauge "Waiting 10 seconds for network link to come up..." 6 60 0
    if ! getent hosts www.google.com &>"${_LOG}"; then
        _dialog --title " ERROR " --no-mouse --infobox "Your network is not working correctly, please configure again!" 3 60
        sleep 3
        return 1
    fi
}

_check
while true; do
    _network && break
done
_cleanup
