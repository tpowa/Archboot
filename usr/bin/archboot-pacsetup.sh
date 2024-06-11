#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Pacman Configuration"

_task_download_mirror() {
    ${_DLPROG} -o /tmp/pacman_mirrorlist.txt "https://www.archlinux.org/mirrorlist/?country=${_COUNTRY}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
    rm /.archboot
}

_download_mirror() {
    : > /.archboot
    _task_download_mirror &
    _progress_wait "0" "99" "${_DOWNLOAD}" "0.01"
    _progress "100" "${_DOWNLOAD}"
    sleep 2
}

_select_mirror() {
    # Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _COUNTRY="$(${_DLPROG} "http://ip-api.com/csv/?fields=countryCode")"
        _DOWNLOAD="Downloading latest mirrorlist for Region ${_COUNTRY}..."
        _download_mirror | _dialog --title " Pacman Configuration " --no-mouse --gauge "${_DOWNLOAD}" 6 70 0
        if grep -q '#Server = https:' /tmp/pacman_mirrorlist.txt; then
            mv "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_PACMAN_MIRROR}"
        fi
    fi
    # This regex doesn't honor commenting
    _MIRRORS=$(grep -E -o '(https)://[^/]*' "${_PACMAN_MIRROR}" | sed 's|$| _|g')
    [[ -z ${_MIRRORS} ]] && _MIRRORS=$(grep -E -o '(http)://[^/]*' "${_PACMAN_MIRROR}" | sed 's|$| _|g')
    #shellcheck disable=SC2086
    _dialog --cancel-label "${_LABEL}" --title " Package Mirror " --menu "" 13 55 7 \
    "Custom Mirror" "_"  ${_MIRRORS} 2>${_ANSWER} || return 1
    #shellcheck disable=SC2155
    local _SERVER=$(cat "${_ANSWER}")
    if [[ "${_SERVER}" == "Custom Mirror" ]]; then
        _dialog  --inputbox "Enter the full URL to repositories." 8 65 \
            "" 2>"${_ANSWER}" || _SYNC_URL=""
            _SYNC_URL=$(cat "${_ANSWER}")
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        _SYNC_URL=$(grep -E -o "${_SERVER}.*" "${_PACMAN_MIRROR}" | head -n1)
    fi
    echo "Using mirror: ${_SYNC_URL}" >"${_LOG}"
    # comment already existing entries
    sed -i -e 's|^Server|#Server|g' "${_PACMAN_MIRROR}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${_SYNC_URL}"" >> "${_PACMAN_MIRROR}"
    if ! pacman -Sy &>${_LOG}; then
        _dialog --title " ERROR " --no-mouse --infobox "Your selected mirror is not working correctly, please configure again!" 3 75
        sleep 3
        _SYNC_URL=""
    fi
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

_task_pacman_keyring_install() {
    _pacman_keyring
    _KEYRING="archlinux-keyring"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy --noconfirm --noprogressbar ${_KEYRING} &>"${_LOG}"
    rm /.archboot
}
_prepare_pacman() {
    : > /.archboot
    _task_pacman_keyring_install &
    _progress_wait "0" "99" "Updating Arch Linux keyring..." "0.15"
    _progress "100" "Arch Linux keyring is ready."
    sleep 2
}

_task_update_environment() {
    _UPDATE_ENVIRONMENT=""
    _LOCAL_KERNEL=""
    _ONLINE_KERNEL=""
    pacman -Sy &>"${_LOG}"
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
    if ! [[ "${_LOCAL_KERNEL}" == "${_ONLINE_KERNEL}" ]]; then
        echo "${_ONLINE_KERNEL}" > /.new_kernel
    fi
    rm /.archboot
}
_update_environment() {
    : > /.archboot
    _task_update_environment &
    _progress_wait "0" " 97" "Checking on new online kernel version..." "0.025"
    if ! [[ -f "/.new_kernel" ]]; then
        _progress "98" "No new kernel online available. Skipping update environment."
        sleep 1
        _progress "100" "Pacman configuration completed successfully."
        sleep 2
    else
        _progress "100" "New kernel online available. Asking for update..."
        sleep 2
    fi
}

_check
if [[ ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
    if ! ping -c1 www.google.com &>"${_NO_LOG}"; then
        _dialog --title " ERROR " --no-mouse --infobox "Your network is not working. Please reconfigure it." 3 60
        sleep 5
        _abort
    fi
fi
while true; do
    if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        _dialog --title " Pacman Configuration " --no-mouse --infobox "Setting local mirror..." 3 40
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
    else
        if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
            _enable_testing
        fi
        _SYNC_URL=""
        while [[ -z "${_SYNC_URL}" ]]; do
            _select_mirror || _abort
        done
    fi
    if _prepare_pacman | _dialog --title " Pacman Configuration " --no-mouse --gauge "Update Arch Linux keyring..." 6 70 0; then
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
        _update_environment | _dialog --title " Pacman Configuration " --no-mouse --gauge "Checking on new online kernel version..." 6 70 0
        if [[ -e /.new_kernel ]]; then
            _dialog --title " New Kernel Available " --defaultno --yesno "Do you want to update the Archboot Environment to $(cat /.new_kernel)?\n\nATTENTION:\nThis will reboot the system using kexec!" 9 60 && _UPDATE_ENVIRONMENT=1
            if [[ -n "${_UPDATE_ENVIRONMENT}" ]]; then
                _run_update_environment
            fi
            _dialog --title " Success " --no-mouse --infobox "Pacman configuration completed successfully." 3 60
            sleep 2
            rm /.new_kernel
        fi
        _cleanup
fi
_dialog --title " Success " --no-mouse --infobox "Pacman configuration completed successfully." 3 60
sleep 2
_cleanup
# vim: set ft=sh ts=4 sw=4 et:
