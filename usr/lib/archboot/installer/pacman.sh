#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_getsource() {
    _PACMAN_CONF=""
    if [[ -e "${_LOCAL_DB}" ]]; then
        _NEXTITEM="4"
        _local_pacman_conf
    else
        _select_mirror || return 1
    fi
    _S_SRC=1
}

_select_mirror() {
    _NEXTITEM="3"
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        dialog --cancel-label "Back" --infobox "Downloading latest mirrorlist..." 3 40
        ${_DLPROG} "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
        if grep -q '#Server = http:' /tmp/pacman_mirrorlist.txt; then
            mv "${_MIRRORLIST}" "${_MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    _MIRRORS=$(grep -E -o '((http)|(https))://[^/]*' "${_MIRRORLIST}" | sed 's|$| _|g')
    #shellcheck disable=SC2086
    _dialog --menu "Select a mirror:" 14 55 7 \
        ${_MIRRORS} \
        "Custom" "_" 2>${_ANSWER} || return 1
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
    _NEXTITEM="4"
    echo "Using mirror: ${_SYNC_URL}" >"${_LOG}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${_SYNC_URL}"" >> /etc/pacman.d/mirrorlist
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

_update_environment() {
    if [[ -d "/var/cache/pacman/pkg" ]] && [[ -n "$(ls -A "/var/cache/pacman/pkg")" ]]; then
        echo "Packages are already in pacman cache..."  >"${_LOG}"
        _dialog --infobox "Packages are already in pacman cache.\nSkipping update environment.\nContinuing in 5 seconds..." 5 50
        sleep 5
    else
        _UPDATE_ENVIRONMENT=""
        _LOCAL_KERNEL=""
        _ONLINE_KERNEL=""
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
                echo "${_LOCAL_KERNEL} local kernel version and ${_ONLINE_KERNEL} online kernel version." >"${_LOG}"
                sleep 2
                if [[ "${_LOCAL_KERNEL}" == "${_ONLINE_KERNEL}" ]]; then
                    _dialog --infobox "No new kernel online available.\nSkipping update environment.\nContinuing in 5 seconds..." 5 50
                    sleep 5
                else
                    _dialog --defaultno --yesno "New online kernel version ${_ONLINE_KERNEL} available.\n\nDo you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nThis will reboot the system using kexec!" 11 60 && _UPDATE_ENVIRONMENT=1
                    if [[ -n "${_UPDATE_ENVIRONMENT}" ]]; then
                        clear
                        echo -e "\e[93mGo and get a cup of coffee. Depending on your system setup,\e[m"
                        echo -e "\e[93myou can \e[1mstart\e[m\e[93m with your tasks in about \e[1m5\e[m\e[93m minutes...\e[m"
                        echo -e "\e[1mStarting\e[m assembling of archboot environment \e[1mwith\e[m package cache..."
                        echo -e "\e[1mRunning now: \e[92mupdate -latest-install\e[m"
                        update -latest-install
                    fi
                fi
            fi
        fi
    fi
}

_prepare_pacman() {
    _NEXTITEM="5"
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
    if ! pacman -Sy ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} &>"${_LOG}"; then
        _dialog --msgbox "Keyring update failed! Check ${_LOG} for errors." 6 60
        return 1
    fi
}

_run_pacman(){
    _chroot_mount
    _dialog --infobox "Pacman is running...\n\nInstalling package(s) to ${_DESTDIR}:\n${_PACKAGES}...\n\nCheck ${_VC} console (ALT-F${_VC_NUM}) for progress..." 10 70
    echo "Installing Packages..." >/tmp/pacman.log
    sleep 5
    #shellcheck disable=SC2086,SC2069
    ${_PACMAN} -Sy ${_PACKAGES} |& tee -a "${_LOG}" /tmp/pacman.log &>"${_NO_LOG}"
    echo $? > /tmp/.pacman-retcode
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
    else
        echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
    fi
    # pacman finished, display scrollable output
    local _RESULT=''
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        _RESULT="Installation Failed (see errors below)"
        _dialog --title "${_RESULT}" --exit-label "Continue" \
        --textbox "/tmp/pacman.log" 18 70 || return 1
    else
        _dialog --infobox "Package installation complete.\nContinuing in 5 seconds..." 4 40
        sleep 5
    fi
    rm /tmp/.pacman-retcode
    # ensure the disk is synced
    sync
    _chroot_umount
}

_install_packages() {
    _destdir_mounts || return 1
    if [[ -z "${_S_SRC}" ]]; then
        _select_source || return 1
    fi
    _prepare_pacman || return 1
    _PACKAGES=""
    # add packages from archboot defaults
    _PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${_PACKAGES}" ]] && _PACKAGES="base linux linux-firmware"
    _auto_packages
    # fix double spaces
    _PACKAGES="${_PACKAGES//  / }"
    _dialog --yesno "Next step will install the following packages for a minimal system:\n${_PACKAGES}\n\nYou can watch the progress on your ${_VC} console.\n\nDo you wish to continue?" 12 75 || return 1
    _run_pacman
    _NEXTITEM="6"
    _chroot_mount
    # automagic time!
    # any automatic configuration should go here
    _dialog --infobox "Writing base configuration..." 6 40
    _auto_timesetting
    _auto_network
    _auto_fstab
    _auto_scheduler
    _auto_swap
    _auto_mdadm
    _auto_luks
    _auto_pacman_keyring
    _auto_testing
    _auto_pacman_mirror
    _auto_vconsole
    _auto_hostname
    _auto_locale
    _auto_bash
    # tear down the chroot environment
    _chroot_umount
}
# vim: set ft=sh ts=4 sw=4 et:
