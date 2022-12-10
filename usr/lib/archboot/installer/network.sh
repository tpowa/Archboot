#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# list all net devices with mac adress
net_interfaces() {
    find /sys/class/net/* -type l ! -name 'lo' -printf '%f ' -exec cat {}/address \;
}

# check for already active profile
check_nework() {
    [[ "${S_NET}" == "1" ]] || donetwork
}

# scan for available essids
essid_scan() {
    # scan the area
    iwctl station "${INTERFACE}" scan
    # only show lines with signal '*'
    # kill spaces from the end and replace spaces with # between
    for dev in $(iwctl station "${INTERFACE}" get-networks | grep '\*' | cut -c 1-41 | sed -e 's|\ *.$||g' -e 's|^.*\ \ ||g' -e 's| |#|g'); do
        echo "${dev}"
        [[ "${1}" ]] && echo "${1}"
    done
}

do_wireless() {
    WLAN_HIDDEN=""
    WLAN_SSID=""
    WLAN_KEY=""
    WLAN_AUTH=""
    if [[ "${CONNECTION}" == "wireless" ]]; then
        # disconnect the interface first!
        iwctl station "${INTERFACE}" disconnect
        # clean old keys first!
        rm -f /var/lib/iwd/*
        #shellcheck disable=SC2086,SC2046
        DIALOG --menu "Choose your SSID:" 14 60 7 \
        $(essid_scan _) \
            "Hidden" "_" 2>"${ANSWER}" || return 1
        WLAN_SSID=$(cat "${ANSWER}")
        WLAN_CONNECT="connect"
        if [[ "${WLAN_SSID}" = "Hidden" ]]; then
            DIALOG --inputbox "Enter the hidden SSID:" 8 65 \
                "secret" 2>"${ANSWER}" || return 1
            WLAN_SSID=$(cat "${ANSWER}")
            WLAN_CONNECT="connect-hidden"
            WLAN_HIDDEN="yes"
        fi
        # replace # with spaces again
        #shellcheck disable=SC2001,SC2086
        WLAN_SSID="$(echo ${WLAN_SSID} | sed -e 's|#|\ |g')"
        #shellcheck disable=SC2001,SC2086
        while [[ -z "${WLAN_AUTH}" ]]; do
            # expect hidden network has a WLAN_KEY
            #shellcheck disable=SC2143
            if ! [[ "$(iwctl station "${INTERFACE}" get-networks | grep -w "${WLAN_SSID}" | cut -c 42-49 | grep -q 'open')" ]] || [[ "${WLAN_CONNECT}" == "connect-hidden" ]]; then
                DIALOG --inputbox "Enter your KEY:" 8 50 "SecretWirelessKey" 2>"${ANSWER}" || return 1
                WLAN_KEY=$(cat "${ANSWER}")
            fi
            # time to connect
            DIALOG --infobox "Connection to ${WLAN_SSID} with ${INTERFACE} ..." 3 70
            if [[ -z "${WLAN_KEY}" ]]; then
                iwctl station "${INTERFACE}" "${WLAN_CONNECT}" "${WLAN_SSID}" && WLAN_AUTH="1"
            else
                iwctl --passphrase="${WLAN_KEY}" station "${INTERFACE}" "${WLAN_CONNECT}" "${WLAN_SSID}" && WLAN_AUTH="1"
            fi
            if [[ "${WLAN_AUTH}" == "1" ]]; then
                DIALOG --infobox "Authentification successfull. Continuing in 3 seconds ..." 3 70
                sleep 3
            else
                DIALOG --msgbox "Error:\nAuthentification failed. Please configure again!" 6 60
            fi
        done
    fi
}

# donetwork()
# Hand-hold through setting up networking
#
# args: none
# returns: 1 on failure
donetwork() {
    S_NET=0
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
        echo "${INTERFACE}" >/tmp/.network-interface
        # iwd renames wireless devices to wlanX
        if echo "${INTERFACE}" | grep -q wlan >/dev/null; then
            CONNECTION="wireless"
        else
            CONNECTION="ethernet"
        fi
        # profile name
        NETWORK_PROFILE=""
        DIALOG --inputbox "Enter your network profile name:" 7 40 "${INTERFACE}-${CONNECTION}" 2>"${ANSWER}" || return 1
        NETWORK_PROFILE=/etc/systemd/network/$(cat "${ANSWER}").network
        # wifi setup first
        do_wireless
        # dhcp switch
        IP=""
        DIALOG --yesno "Do you want to use DHCP?" 5 40
        #shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then
            IP="dhcp"
        else
            IP="static"
            DIALOG --inputbox "Enter your IP address and netmask:" 7 40 "192.168.1.23/24" 2>"${ANSWER}" || return 1
            IPADDR=$(cat "${ANSWER}")
            DIALOG --inputbox "Enter your gateway:" 7 40 "192.168.1.1" 2>"${ANSWER}" || return 1
            GW=$(cat "${ANSWER}")
            DIALOG --inputbox "Enter your DNS server IP:" 7 40 "192.168.1.1" 2>"${ANSWER}" || return 1
            DNS=$(cat "${ANSWER}")
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
        DIALOG --yesno "Are these settings correct?\n\nInterface:    ${INTERFACE}\nConnection:   ${CONNECTION}\nNetwork profile: ${NETWORK_PROFILE}\nSSID:      ${WLAN_SSID}\nHidden:     ${WLAN_HIDDEN}\nKey:        ${WLAN_KEY}\ndhcp or static: ${IP}\nIP address: ${IPADDR}\nGateway:    ${GW}\nDNS server: ${DNS}\nProxy setting: ${PROXY}" 0 0
        case $? in
            1) ;;
            0) NETPARAMETERS="1" ;;
        esac
    done
    # write systemd-networkd profile
    echo "#$NETWORK_PROFILE generated by archboot setup" > "${NETWORK_PROFILE}"
    #shellcheck disable=SC2129
    echo "[Match]"  >> "${NETWORK_PROFILE}"
    echo "Name=${INTERFACE}" >> "${NETWORK_PROFILE}"
    echo "" >> "${NETWORK_PROFILE}"
    echo "[Network]" >> "${NETWORK_PROFILE}"
    [[ "${IP}" == "dhcp" ]] && echo "DHCP=yes" >> "${NETWORK_PROFILE}"
    if [[ "${CONNECTION}" = "wireless" ]]; then
        #shellcheck disable=SC2129
        echo "IgnoreCarrierLoss=3s" >>"${NETWORK_PROFILE}"
    fi
    if [[ "${IP}" = "static" ]]; then
        #shellcheck disable=SC2129
        echo "Address=${IPADDR}" >>"${NETWORK_PROFILE}"
        echo "Gateway=${GW}" >>"${NETWORK_PROFILE}"
        echo "DNS=${DNS}" >>"${NETWORK_PROFILE}"
    fi
    if [[ -e /etc/systemd/network/10-wired-auto-dhcp.network ]]; then
        echo "Disabled Archboot's bootup wired auto dhcp browsing." > "${LOG}"
        rm /etc/systemd/network/10-wired-auto-dhcp.network
    fi
    echo "Using setup's network profile ${NETWORK_PROFILE} now..." > "${LOG}"
    systemctl restart systemd-networkd
    NETWORK_COUNT="0"
    DIALOG --infobox "Waiting 30 seconds for network link to come up ..." 3 60
    # add sleep here dhcp can need some time to get link
    while ! ping -c1 www.google.com > "${LOG}" 2>&1; do
        sleep 1
        NETWORK_COUNT="$((NETWORK_COUNT+1))"
        [[ "${NETWORK_COUNT}" == "30" ]] && break
    done
    if ! grep -qw up /sys/class/net/"${INTERFACE}"/operstate; then
        DIALOG --msgbox "Error:\nYour network is not working correctly, please configure again!" 4 70
        return 1
    else
        DIALOG --infobox "Link is up. Continuing in 3 seconds ..." 3 60
        sleep 3
    fi
    NEXTITEM="2"
    S_NET=1
}
