#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Pacman Configuration"

_select_mirror() {
    # Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _COUNTRY="$(curl -s "http://ip-api.com/csv/?fields=countryCode")"
        _dialog --no-mouse --infobox "Downloading latest mirrorlist for Region ${_COUNTRY}..." 3 60
        ${_DLPROG} "https://www.archlinux.org/mirrorlist/?country=${_COUNTRY}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
        sleep 2
        if grep -q '#Server = https:' /tmp/pacman_mirrorlist.txt; then
            mv "${_MIRRORLIST}" "${_MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_MIRRORLIST}"
        fi
    fi
    # This regex doesn't honor commenting
    _MIRRORS=$(grep -E -o '(https)://[^/]*' "${_MIRRORLIST}" | sed 's|$| _|g')
    [[ -z ${_MIRRORS} ]] && _MIRRORS=$(grep -E -o '(http)://[^/]*' "${_MIRRORLIST}" | sed 's|$| _|g')
    _SYNC_URL=""
    while [[ -z "${_SYNC_URL}" ]]; do
        #shellcheck disable=SC2086
        _dialog --cancel-label "Exit" --title " Package Mirror " --menu "" 13 55 7 \
        "Custom Mirror" "_"  ${_MIRRORS} 2>${_ANSWER} || _abort
        #shellcheck disable=SC2155
        local _SERVER=$(cat "${_ANSWER}")
        if [[ "${_SERVER}" == "Custom Mirror" ]]; then
            _dialog --cancel-label "Back" --inputbox "Enter the full URL to repositories." 8 65 \
                "" 2>"${_ANSWER}" || _SYNC_URL=""
                _SYNC_URL=$(cat "${_ANSWER}")
        else
            # Form the full URL for our mirror by grepping for the server name in
            # our mirrorlist and pulling the full URL out. Substitute 'core' in
            # for the repository name, and ensure that if it was listed twice we
            # only return one line for the mirror.
            _SYNC_URL=$(grep -E -o "${_SERVER}.*" "${_MIRRORLIST}" | head -n1)
        fi
    done
    echo "Using mirror: ${_SYNC_URL}" >"${_LOG}"
    # comment already existing entries
    sed -i -e 's|^Server|#Server|g' /etc/pacman.d/mirrorlist
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${_SYNC_URL}"" >> /etc/pacman.d/mirrorlist
    return 0
}

_enable_testing() {
    if ! grep -q "^\[.*testing\]" /etc/pacman.conf; then
        _DOTESTING=""
        _dialog --title " Testing Repositories " --defaultno --yesno "Do you want to enable testing repositories?\n\nOnly enable this if you need latest\navailable packages for testing purposes!" 8 50 && _DOTESTING=1
        if [[ -n "${_DOTESTING}" ]]; then
            sed -i -e '/^#\[core-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e '/^#\[extra-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e 's:^#\[core-testing\]:\[core-testing\]:g' -e  's:^#\[extra-testing\]:\[extra-testing\]:g' /etc/pacman.conf
        fi
    else
        _DOTESTING=1
    fi
}

_prepare_pacman() {
    _dialog --no-mouse --infobox "Waiting for Arch Linux keyring initialization..." 3 40
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    _dialog --no-mouse --infobox "Update Arch Linux keyring..." 3 50
    _KEYRING="archlinux-keyring"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    if ! pacman -Sy --noconfirm --noprogressbar ${_KEYRING} &>"${_LOG}"; then
        _dialog --title " ERROR " --no-mouse --infobox "Keyring update failed! Check ${_LOG} for errors." 3 60
        sleep 5
        return 1
    fi
}

_update_environment() {
    _UPDATE_ENVIRONMENT=""
    _LOCAL_KERNEL=""
    _ONLINE_KERNEL=""
    pacman -Sy &>"${_LOG}"
    _progress "50" "Checking on new online kernel version..."
    #shellcheck disable=SC2086
    _LOCAL_KERNEL="$(pacman -Qi ${_KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
    if  [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        #shellcheck disable=SC2086
        _ONLINE_KERNEL="$(pacman -Si ${_KERNELPKG}-${_RUNNING_ARCH} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
    else
        if [[ -n "${_DOTESTING}" ]]; then
            #shellcheck disable=SC2086
            _ONLINE_KERNEL="$(pacman -Si core-testing/${_KERNELPKG} 2>${_NO_LOG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
        fi
        if [[ -z "${_ONLINE_KERNEL}" ]]; then
            #shellcheck disable=SC2086
            _ONLINE_KERNEL="$(pacman -Si ${_KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
        fi
    fi
    sleep 2
    echo "${_LOCAL_KERNEL} local kernel version and ${_ONLINE_KERNEL} online kernel version." >"${_LOG}"
    if [[ "${_LOCAL_KERNEL}" == "${_ONLINE_KERNEL}" ]]; then
        _progress "98" "No new kernel online available. Skipping update environment."
        sleep 2
    else
        _dialog --title " New Kernel Available " --defaultno --yesno "Do you want to update the Archboot Environment to ${_ONLINE_KERNEL}?\n\nATTENTION:\nThis will reboot the system using kexec!" 9 60 && _UPDATE_ENVIRONMENT=1
        if [[ -n "${_UPDATE_ENVIRONMENT}" ]]; then
            _run_update_environment
        fi
    fi
    _progress "100" "Pacman configuration completed successfully."
    sleep 2
}

_check
if [[ ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
    if ! ping -c1 www.google.com &>/dev/null; then
        _dialog --title " ERROR " --no-mouse --infobox "Your network is not working. Please reconfigure it." 3 60
        sleep 5
        _abort
    fi
fi
while true; do
    if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        _dialog --no-mouse --infobox "Setting local mirror..." 3 40
        _PACMAN_CONF="/etc/pacman.conf"
        cat << EOF > "${_PACMAN_CONF}"
[options]
Architecture = auto
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
[archboot]
Server = file:///var/cache/pacman/pkg
EOF
        pacman -Sy >>"${_LOG}"
        sleep 2
        break
    fi
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _enable_testing
    fi
    _select_mirror
    if _prepare_pacman; then
        break
    else
        _dialog --title " ERROR " --no-mouse --infobox "Please reconfigure pacman." 3 40
        sleep 3
    fi
done
if [[ ! -e "/var/cache/pacman/pkg/archboot.db" ]] &&\
    update | grep -q '\-latest' &&\
    [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "2571000" ]] &&\
    ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        _update_environment | _dialog --title "Logging to ${_LOG}" --no-mouse --gauge "Refreshing package database..." 6 70 0
        _cleanup
fi
_dialog --no-mouse --infobox "Pacman configuration completed successfully." 3 60
sleep 2
_cleanup
# vim: set ft=sh ts=4 sw=4 et:
