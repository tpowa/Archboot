#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Pacman Configuration"
_DLPROG="wget -q"
_MIRRORLIST="/etc/pacman.d/mirrorlist"

_select_mirror() {
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _dialog --infobox "Downloading latest mirrorlist..." 3 40
        ${_DLPROG} "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
        if grep -q '#Server = http:' /tmp/pacman_mirrorlist.txt; then
            mv "${_MIRRORLIST}" "${_MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    _MIRRORS=$(grep -E -o '((http)|(https))://[^/]*' "${_MIRRORLIST}" | sed 's|$| _|g')
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " Pacman Package Mirror " --menu "" 13 55 7 \
    "Custom" "_"  ${_MIRRORS} 2>${_ANSWER} || return 1
    #shellcheck disable=SC2155
    local _SERVER=$(cat "${_ANSWER}")
    if [[ "${_SERVER}" == "Custom" ]]; then
        _dialog --inputbox "Enter the full URL to repositories." 8 65 \
            "" 2>"${_ANSWER}" || return 1
            _SYNC_URL=$(cat "${_ANSWER}")
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        _SYNC_URL=$(grep -E -o "${_SERVER}.*" "${_MIRRORLIST}" | head -n1)
    fi
    echo "Using mirror: ${_SYNC_URL}" >"${_LOG}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${_SYNC_URL}"" >> /etc/pacman.d/mirrorlist
    return 0
}

_enable_testing() {
    if ! grep -q "^\[.*testing\]" /etc/pacman.conf; then
        _DOTESTING=""
        _dialog --defaultno --yesno "Do you want to enable [core-testing]\nand [extra-testing] repositories?\n\nOnly enable this if you need latest\navailable packages for testing purposes!" 9 50 && _DOTESTING=1
        if [[ -n "${_DOTESTING}" ]]; then
            sed -i -e '/^#\[core-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e '/^#\[extra-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e 's:^#\[core-testing\]:\[core-testing\]:g' -e  's:^#\[extra-testing\]:\[extra-testing\]:g' /etc/pacman.conf
        fi
    fi
}

_prepare_pacman() {
    # Set up the necessary directories for pacman use
    [[ ! -d "${_DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${_DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${_DESTDIR}/var/lib/pacman" ]] && mkdir -p "${_DESTDIR}/var/lib/pacman"
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
    _dialog --infobox "Update Arch Linux keyring..." 3 40
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
                _dialog --infobox "Refreshing package database..." 3 70
                pacman -Sy &>"${_LOG}"
                sleep 1
                _dialog --infobox "Checking on new online kernel version..." 3 70
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
                    _dialog --infobox "No new kernel online available.\nSkipping update environment." 4 50
                    sleep 3
                else
                    _dialog --defaultno --yesno "New online kernel version ${_ONLINE_KERNEL} available.\n\nDo you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nThis will reboot the system using kexec!" 11 60 && _UPDATE_ENVIRONMENT=1
                    if [[ -n "${_UPDATE_ENVIRONMENT}" ]]; then
                        clear
                        echo -e "\e[93mGo and get a cup of coffee. Depending on your system setup,\e[m"
                        echo -e "\e[93myou can \e[1mstart\e[m\e[93m with your tasks in about \e[1m5\e[m\e[93m minutes...\e[m"
                        if update | grep -q latest-install; then
                            update -latest-install
                        else
                            update -latest
                        fi
                    fi
                fi
            fi
        fi
    fi
}

_check
while true; do
    _enable_testing
    _select_mirror && break
done
_prepare_pacman || exit 1
_update_environment
_cleanup
# vim: set ft=sh ts=4 sw=4 et:
