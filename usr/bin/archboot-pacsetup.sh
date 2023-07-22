#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Pacman Configuration"

_select_mirror() {
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _COUNTRY="$(curl -s "http://ip-api.com/csv/?fields=countryCode")"
        _dialog --infobox "Downloading latest mirrorlist for Region ${_COUNTRY}..." 3 60
        ${_DLPROG} "https://www.archlinux.org/mirrorlist/?country=${_COUNTRY}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
        sleep 2
        if grep -q '#Server = https:' /tmp/pacman_mirrorlist.txt; then
            mv "${_MIRRORLIST}" "${_MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    _MIRRORS=$(grep -E -o '(https)://[^/]*' "${_MIRRORLIST}" | sed 's|$| _|g')
    _SYNC_URL=""
    while [[ -z "${_SYNC_URL}" ]]; do
        #shellcheck disable=SC2086
        _dialog --cancel-label "Exit" --title " Package Mirror " --menu "" 13 55 7 \
        "Custom" "_"  ${_MIRRORS} 2>${_ANSWER} || _abort
        #shellcheck disable=SC2155
        local _SERVER=$(cat "${_ANSWER}")
        if [[ "${_SERVER}" == "Custom" ]]; then
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
    fi
}

_prepare_pacman() {
    _dialog --infobox "Waiting for Arch Linux keyring initialization..." 3 40
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    _dialog --infobox "Update Arch Linux keyring..." 3 50
    _KEYRING="archlinux-keyring"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    if ! pacman -Sy --noconfirm --noprogressbar ${_KEYRING} &>"${_LOG}"; then
        _dialog --title " ERROR " --infobox "Keyring update failed! Check ${_LOG} for errors." 3 60
        sleep 5
        return 1
    fi
}

_update_environment() {
    _UPDATE_ENVIRONMENT=""
    _LOCAL_KERNEL=""
    _ONLINE_KERNEL=""
    if update | grep -q '\-latest'; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "2571000" ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                _dialog --infobox "Refreshing package database..." 3 50
                pacman -Sy &>"${_LOG}"
                sleep 1
                _dialog --infobox "Checking on new online kernel version..." 3 50
                #shellcheck disable=SC2086
                _LOCAL_KERNEL="$(pacman -Qi ${_KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                if  [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
                    #shellcheck disable=SC2086
                _   ONLINE_KERNEL="$(pacman -Si ${_KERNELPKG}-${_RUNNING_ARCH} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
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
                echo "${_LOCAL_KERNEL} local kernel version and ${_ONLINE_KERNEL} online kernel version." >"${_LOG}"
                sleep 2
                if [[ "${_LOCAL_KERNEL}" == "${_ONLINE_KERNEL}" ]]; then
                    _dialog --infobox "No new kernel online available. Skipping update environment." 3 70
                    sleep 2
                else
                    _dialog --title " New Kernel Available " --defaultno --yesno "Do you want to update the Archboot Environment to ${_ONLINE_KERNEL}?\n\nATTENTION:\nThis will reboot the system using kexec!" 9 60 && _UPDATE_ENVIRONMENT=1
                    if [[ -n "${_UPDATE_ENVIRONMENT}" ]]; then
                        _run_update_environment
                    fi
                fi
            fi
        fi
    fi
}

_check
if [[ ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
    if ! ping -c1 www.google.com &>/dev/null; then
        _dialog --title " ERROR " --infobox "Your network is not working. Please reconfigure it." 3 60
        sleep 5
        _abort
    fi
fi
while true; do
    if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        _dialog --infobox "Setting local mirror..." 3 40
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
    _enable_testing
    _select_mirror || exit 1
    if _prepare_pacman; then
        break
    else
        _dialog --title " ERROR " --infobox "Please reconfigure pacman." 3 40
        sleep 5
    fi
done
if [[ ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
    _update_environment
fi
_dialog --infobox "Pacman configuration completed successfully." 3 60
sleep 2
_cleanup
# vim: set ft=sh ts=4 sw=4 et:
