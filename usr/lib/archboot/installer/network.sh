#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# list all net devices with mac adress
net_interfaces() {
    find /sys/class/net/* -type l ! -name 'lo' -printf '%f ' -exec cat {}/address \;
}

# check for already active profile
check_nework() {
    for i in /etc/netctl/*; do
        [[ -f "${i}" ]] && netctl is-active "$(basename "${i}")" && S_NET=1
    done
    [[ "${S_NET}" == "1" ]] || donetwork
}

# scan for available essids
essid_scan() {
    for dev in $(iw dev "${INTERFACE}" scan | grep SSID | cut -d ':' -f2 | sort -u | sed -e 's#^ ##g' -e 's| |#|g'); do
        echo "${dev}"
        [[ "${1}" ]] && echo "${1}"
    done
}

# donetwork()
# Hand-hold through setting up networking
#
# args: none
# returns: 1 on failure
donetwork() {
    NETPARAMETERS=""
    while [[ "${NETPARAMETERS}" = "" ]]; do
        # select network interface
        INTERFACE=
        ifaces=$(net_interfaces)
        while [[ "${INTERFACE}" = "" ]]; do
            #shellcheck disable=SC2086
            DIALOG --ok-label "Select" --menu "Select a network interface:" 14 55 7 ${ifaces} 2>"${ANSWER}"
            case $? in
                1) return 1 ;;
                0) INTERFACE=$(cat "${ANSWER}") ;;
            esac
        done
        # wireless switch
        CONNECTION=""
        WLAN_HIDDEN=""
        WLAN_ESSID=""
        WLAN_SECURITY=""
        WLAN_KEY=""
        # iwd renames wireless devices to wlanX
        if echo "${INTERFACE}" | grep -q wlan >/dev/null; then
            CONNECTION="wireless"
            # bring interface up for essid scan
            ip link set dev "${INTERFACE}" up
            DIALOG --infobox "Scanning for ESSIDs ..." 3 40
            #shellcheck disable=SC2086
            DIALOG --menu "Choose your ESSID:" 14 55 7 \
            $(essid_scan _) \
             "Hidden" "_" 2>"${ANSWER}" || return 1
            local WLAN_ESSID=$(cat "${ANSWER}")
            if [[ "${WLAN_ESSID}" = "Hidden" ]]; then
                DIALOG --inputbox "Enter the hidden ESSID:" 8 65 \
                    "secret" 2>"${ANSWER}" || return 1
                WLAN_ESSID=$(cat "${ANSWER}")
                WLAN_HIDDEN="yes"
            fi
            # remove spaces
            #shellcheck disable=SC2001,SC2086
            WLAN_ESSID="$(echo ${WLAN_ESSID} | sed -e 's|#|\ |g')"
            WPA=""
            WEP=""
            DIALOG --infobox "Checking on WPA/PSK encryption ..." 3 40
            iw dev "${INTERFACE}" scan | grep -q 'RSN:' && WPA="1"
            iw dev "${INTERFACE}" scan | grep -q 'WPA:' && WPA="1"
            DIALOG --infobox "Checking on WEP encryption ..." 3 40
            iw dev "${INTERFACE}" scan | grep -q 'Privacy:' && WEP="1"
            #shellcheck disable=SC2181
            while [[ "${WLAN_SECURITY}" = "" ]]; do
                DIALOG --ok-label "Select" --menu "Select encryption type:" 9 40 7 \
                    $([[ "${WPA}" == "1" ]] && echo "wpa" "WPA/PSK") \
                    $([[ "${WEP}" == "1" ]] && echo "wep" "WEP") \
                    "none" "NO encryption" 2>"${ANSWER}"
                    case $? in
                        1) return 1 ;;
                        0) WLAN_SECURITY=$(cat "${ANSWER}") ;;
                    esac
            done
            if [[ "${WLAN_SECURITY}" == "wpa" || "${WLAN_SECURITY}" == "wep" ]]; then
                DIALOG --inputbox "Enter your KEY:" 5 40 "WirelessKey" 2>"${ANSWER}" || return 1
                WLAN_KEY=$(cat "${ANSWER}")
            fi
        else
            CONNECTION="ethernet"
        fi
        # dhcp switch
        IP=""
        DHCLIENT=""
        DIALOG --yesno "Do you want to use DHCP?" 5 40
        #shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            IP="dhcp"
            DIALOG --defaultno --yesno "Do you want to use dhclient instead of dhcpcd?" 5 55
            #shellcheck disable=SC2181
            [[ $? -eq 0 ]] && DHCLIENT="yes"

        else
            IP="static"
            DIALOG --inputbox "Enter your IP address and netmask:" 7 40 "192.168.1.23/24" 2>"${ANSWER}" || return 1
            IPADDR=$(cat "${ANSWER}")
            DIALOG --inputbox "Enter your gateway:" 7 40 "192.168.1.1" 2>"${ANSWER}" || return 1
            GW=$(cat "${ANSWER}")
            DIALOG --inputbox "Enter your DNS server IP:" 7 40 "192.168.1.1" 2>"${ANSWER}" || return 1
            DNS=$(cat "${ANSWER}")
        fi
        DIALOG --yesno "Are these settings correct?\n\nInterface:    ${INTERFACE}\nConnection:   ${CONNECTION}\nESSID:      ${WLAN_ESSID}\nHidden:     ${WLAN_HIDDEN}\nEncryption: ${WLAN_SECURITY}\nKey:        ${WLAN_KEY}\ndhcp or static: ${IP}\nUse dhclient:   ${DHCLIENT}\nIP address: ${IPADDR}\nGateway:    ${GW}\nDNS server: ${DNS}" 0 0
        case $? in
            1) ;;
            0) NETPARAMETERS="1" ;;
        esac
    done
    # profile name
    NETWORK_PROFILE=""
    DIALOG --inputbox "Enter your network profile name:" 7 40 "${INTERFACE}-${CONNECTION}" 2>"${ANSWER}" || return 1
    NETWORK_PROFILE=/etc/netctl/$(cat "${ANSWER}")
    # write profile
    echo "Connection=${CONNECTION}" >"${NETWORK_PROFILE}"
    echo "Description='$NETWORK_PROFILE generated by archboot setup'" >>"${NETWORK_PROFILE}"
    echo "Interface=${INTERFACE}"  >>"${NETWORK_PROFILE}"
    if [[ "${CONNECTION}" = "wireless" ]]; then
        #shellcheck disable=SC2129
        echo "Security=${WLAN_SECURITY}" >>"${NETWORK_PROFILE}"
        echo "ESSID='${WLAN_ESSID}'" >>"${NETWORK_PROFILE}"
        echo "Key='${WLAN_KEY}'" >>"${NETWORK_PROFILE}"
        [[ "${WLAN_HIDDEN}" = "yes" ]] && echo "Hidden=yes" >>"${NETWORK_PROFILE}"
    fi
    echo "IP=${IP}" >>"${NETWORK_PROFILE}"
    if [[ "${IP}" = "dhcp" ]]; then
        [[ "${DHCLIENT}" = "yes" ]] && echo "DHCPClient=dhclient" >>"${NETWORK_PROFILE}"
    else
        #shellcheck disable=SC2129
        echo "Address='${IPADDR}'" >>"${NETWORK_PROFILE}"
        echo "Gateway='${GW}'" >>"${NETWORK_PROFILE}"
        echo "DNS=('${DNS}')" >>"${NETWORK_PROFILE}"
    fi
    # bring down interface first
    systemctl stop dhcpcd@"${INTERFACE}".service
    ip link set dev "${INTERFACE}" down
    # run netctl
    netctl restart "$(basename "${NETWORK_PROFILE}")" >"${LOG}"
    # add sleep here dhcp can need some time to get link
    DIALOG --infobox "Waiting 30 seconds for network link to come up ..." 3 60
    NETWORK_COUNT="0"
    while ! grep -qw up /sys/class/net/"${INTERFACE}"/operstate; do
        sleep 1
        NETWORK_COUNT="$(($NETWORK_COUNT+1))"
        [[ "${NETWORK_COUNT}" == "30" ]] && break
    done
    if ! grep -qw up /sys/class/net/"${INTERFACE}"/operstate; then
        DIALOG --msgbox "Error occured while running netctl. (see 'journalctl -xn' for output)" 0 0
        return 1
    else
        DIALOG --infobox "Link is up. Continuing in 3 seconds ..." 3 60
        sleep 3
    fi
    # http/ftp proxy settings
    DIALOG --inputbox "Enter your proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 13 65 "" 2>"${ANSWER}" || return 1
    PROXY=$(cat "${ANSWER}")
    PROXIES="http_proxy https_proxy ftp_proxy rsync_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY"
    if [[ "${PROXY}" = "" ]]; then
        for i in ${PROXIES}; do
            unset "${i}"
        done
    else
        for i in ${PROXIES}; do
            export "${i}"="${PROXY}"
        done
    fi
    NEXTITEM="2"
    S_NET=1
}
