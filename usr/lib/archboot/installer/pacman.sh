#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# downloader
DLPROG="wget"
_MIRRORLIST="/etc/pacman.d/mirrorlist"

_getsource() {
    _S_SRC=0
    _PACMAN_CONF=""
    if [[ -e "${_LOCAL_DB}" ]]; then
        _NEXTITEM="4"
        local_pacman_conf
        _dialog --msgbox "Setup is running in <Local mode>.\nOnly Local package database is used for package installation.\n\nIf you want to switch to <Online mode>, you have to delete /var/cache/pacman/pkg/archboot.db and rerun this step." 10 70
        _S_SRC=1
    else
        select_mirror || return 1
        _S_SRC=1
    fi
}

# select_mirror()
# Prompt user for preferred mirror and set ${_SYNC_URL}
#
# args: none
# returns: nothing
select_mirror() {
    _NEXTITEM="2"
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        dialog --infobox "Downloading latest mirrorlist ..." 3 40
        ${DLPROG} -q "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt
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
    echo "Using mirror: ${_SYNC_URL}" > "${_LOG}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${_SYNC_URL}"" >> /etc/pacman.d/mirrorlist
}

# dotesting()
# enable testing repository on network install
dotesting() {
    if ! grep -q "^\[testing\]" /etc/pacman.conf; then
        _dialog --defaultno --yesno "Do you want to enable [testing]\nand [community-testing] repositories?\n\nOnly enable this if you need latest\navailable packages for testing purposes!" 9 50 && _DOTESTING="yes"
        if [[ "${_DOTESTING}" == "yes" ]]; then
            sed -i -e '/^#\[testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' /etc/pacman.conf
            sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' /etc/pacman.conf
        fi
    fi
}

# check for updating complete environment with packages
update_environment() {
    if [[ -d "/var/cache/pacman/pkg" ]] && [[ -n "$(ls -A "/var/cache/pacman/pkg")" ]]; then
        echo "Packages are already in pacman cache ..."  > "${_LOG}"
        _dialog --infobox "Packages are already in pacman cache. Continuing in 3 seconds ..." 3 70
        sleep 3
    else
        _UPDATE_ENVIRONMENT=""
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "2571000" ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                _dialog --infobox "Refreshing package database ..." 3 70
                pacman -Sy > "${_LOG}" 2>&1
                sleep 1
                _dialog --infobox "Checking on new online kernel version ..." 3 70
                #shellcheck disable=SC2086
                _LOCAL_KERNEL="$(pacman -Qi ${_KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                if  [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
                    #shellcheck disable=SC2086
                    _ONLINE_KERNEL="$(pacman -Si ${_KERNELPKG}-${_RUNNING_ARCH} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                else
                    #shellcheck disable=SC2086
                    _ONLINE_KERNEL="$(pacman -Si ${_KERNELPKG} | grep Version | cut -d ':' -f2 | sed -e 's# ##')"
                fi
                echo "${_LOCAL_KERNEL} local kernel version and ${_ONLINE_KERNEL} online kernel version." > "${_LOG}"
                sleep 2
                if [[ "${_LOCAL_KERNEL}" == "${_ONLINE_KERNEL}" ]]; then
                    _dialog --infobox "No new kernel online available. Continuing in 3 seconds ..." 3 70
                    sleep 3
                else
                    _dialog --defaultno --yesno "New online kernel version ${_ONLINE_KERNEL} available.\n\nDo you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nThis will reboot the system using kexec!" 0 0 && _UPDATE_ENVIRONMENT="1"
                    if [[ "${_UPDATE_ENVIRONMENT}" == "1" ]]; then
                        _dialog --infobox "Now setting up new archboot environment and dowloading latest packages.\n\nRunning at the moment: update-installer -latest-install\nCheck ${_VC} console (ALT-F${_VC_NUM}) for progress...\n\nGet a cup of coffee ...\nDepending on your system's setup, this needs about 5 minutes.\nPlease be patient." 0 0
                        update-installer -latest-install > "${_LOG}" 2>&1
                    fi
                fi
            fi
        fi
    fi
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
prepare_pacman() {
    _NEXTITEM="5"
    # Set up the necessary directories for pacman use
    [[ ! -d "${_DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${_DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${_DESTDIR}/var/lib/pacman" ]] && mkdir -p "${_DESTDIR}/var/lib/pacman"
    _dialog --infobox "Waiting for Arch Linux keyring initialization ..." 3 40
    # pacman-key process itself
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    _dialog --infobox "Refreshing package database ..." 3 40
    ${PACMAN} -Sy > "${_LOG}" 2>&1 || (_dialog --msgbox "Pacman preparation failed! Check ${_LOG} for errors." 6 60; return 1)
    _dialog --infobox "Update Arch Linux keyring ..." 3 40
    _KEYRING="archlinux-keyring"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} > "${_LOG}" 2>&1 || (_dialog --msgbox "Keyring update failed! Check ${_LOG} for errors." 6 60; return 1)
}

# Set _PACKAGES parameter before running to install wanted packages
run_pacman(){
    # create chroot environment on target system
    # code straight from mkarchroot
    chroot_mount
    _dialog --infobox "Pacman is running...\n\nInstalling package(s) to ${_DESTDIR}:\n${_PACKAGES} ...\n\nCheck ${_VC} console (ALT-F${_VC_NUM}) for progress ..." 10 70
    echo "Installing Packages ..." >/tmp/pacman.log
    sleep 5
    #shellcheck disable=SC2086,SC2069
    ${PACMAN} -S ${_PACKAGES} |& tee -a "${_LOG}" /tmp/pacman.log >/dev/null 2>&1
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
        _dialog --infobox "Package installation complete.\nContinuing in 3 seconds ..." 4 40
        sleep 3
    fi
    rm /tmp/.pacman-retcode
    # ensure the disk is synced
    sync
    chroot_umount
}

# install_packages()
# performs package installation to the target system
install_packages() {
    _destdir_mounts || return 1
    if [[ "${_S_SRC}" == "0" ]]; then
        _select_source || return 1
    fi
    prepare_pacman || return 1
    _PACKAGES=""
    # add packages from archboot defaults
    _PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${_PACKAGES}" ]] && _PACKAGES="base linux linux-firmware"
    auto_packages
    # fix double spaces
    _PACKAGES="${_PACKAGES//  / }"
    _dialog --yesno "Next step will install the following packages for a minimal system:\n${_PACKAGES}\n\nYou can watch the progress on your ${_VC} console.\n\nDo you wish to continue?" 12 75 || return 1
    run_pacman
    _NEXTITEM="6"
    chroot_mount
    # automagic time!
    # any automatic configuration should go here
    _dialog --infobox "Writing base configuration ..." 6 40
    _auto_timesetting
    _auto_network
    _auto_fstab
    _auto_scheduler
    _auto_swap
    _auto_mdadm
    _auto_luks
    _auto_pacman
    _auto_testing
    _auto_pacman_mirror
    _auto_vconsole
    _auto_hostname
    _auto_locale
    _auto_nano_syntax
    # tear down the chroot environment
    chroot_umount
}
