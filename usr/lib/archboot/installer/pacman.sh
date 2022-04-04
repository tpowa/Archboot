#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# downloader
DLPROG="wget"
MIRRORLIST="/etc/pacman.d/mirrorlist"

getsource() {
    S_SRC=0
    PACMAN_CONF=""
    if [[ -e "${LOCAL_DB}" ]]; then
        NEXTITEM="4"
        local_pacman_conf
        DIALOG --msgbox "Setup is running in <Local mode>.\nOnly Local package database is used for package installation.\n\nIf you want to switch to <Online mode>, you have to delete /var/cache/pacman/pkg/archboot.db and rerun this step." 10 70
        S_SRC=1
    else
        select_mirror || return 1
        S_SRC=1
    fi
}

# select_mirror()
# Prompt user for preferred mirror and set ${SYNC_URL}
#
# args: none
# returns: nothing
select_mirror() {
    NEXTITEM="2"
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        dialog --infobox "Downloading latest mirrorlist ..." 3 40
        ${DLPROG} -q "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt -o "${LOG}" 2>/dev/null

        if grep -q '#Server = http:' /tmp/pacman_mirrorlist.txt; then
            mv "${MIRRORLIST}" "${MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    MIRRORS=$(grep -E -o '((http)|(https))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
    #shellcheck disable=SC2086
    DIALOG --menu "Select a mirror" 14 55 7 \
        ${MIRRORS} \
        "Custom" "_" 2>${ANSWER} || return 1
    #shellcheck disable=SC2155
    local _server=$(cat "${ANSWER}")
    if [[ "${_server}" = "Custom" ]]; then
        DIALOG --inputbox "Enter the full URL to repositories." 8 65 \
            "" 2>"${ANSWER}" || return 1
            SYNC_URL=$(cat "${ANSWER}")
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        SYNC_URL=$(grep -E -o "${_server}.*" "${MIRRORLIST}" | head -n1)
    fi
    NEXTITEM="4"
    echo "Using mirror: ${SYNC_URL}" > "${LOG}"
    #shellcheck disable=SC2027,SC2086
    echo "Server = "${SYNC_URL}"" >> /etc/pacman.d/mirrorlist
    if [[ "${DOTESTING}" == "yes" ]]; then
        #shellcheck disable=SC2129
        echo "[testing]" >> /etc/pacman.conf
        echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
        echo "[community-testing]" >> /etc/pacman.conf
        echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
    fi
}

# dotesting()
# enable testing repository on network install
dotesting() {
    DOTESTING=""
    DIALOG --defaultno --yesno "Do you want to enable [testing] repository?\n\nOnly enable this if you need latest available packages for testing purposes!" 8 60 && DOTESTING="yes"
}

# check for updating complete environment with packages
update_environment() {
    if [[ -d "/var/cache/pacman/pkg" ]] && [[ -n "$(ls -A "/var/cache/pacman/pkg")" ]]; then
        echo "Packages are already in pacman cache..."  > "${LOG}"
    else
        detect_uefi_boot
        UPDATE_ENVIRONMENT=""
        if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "0" ]]; then
            DIALOG --defaultno --yesno "Do you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nRequires at least 2.6 GB RAM and will reboot the system using kexec!" 0 0 && UPDATE_ENVIRONMENT="1"
            if [[ "${UPDATE_ENVIRONMENT}" == "1" ]]; then
                DIALOG --infobox "Now setting up new archboot environment and dowloading latest packages.\n\nRunning at the moment: update-installer.sh -latest-install\nCheck ${LOG} for progress...\n\nGet a cup of coffee ...\nDepending on your system's setup this needs about 5 minutes. Please be patient." 0 0
                /usr/bin/update-installer.sh -latest-install > "${LOG}" 2>&1
            fi
        fi
    fi
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
prepare_pacman() {
    # Set up the necessary directories for pacman use
    [[ ! -d "${DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${DESTDIR}/var/lib/pacman" ]] && mkdir -p "${DESTDIR}/var/lib/pacman"
    DIALOG --infobox "Refreshing package database..." 3 40
    ${PACMAN} -Sy > "${LOG}" 2>&1 || (DIALOG --msgbox "Pacman preparation failed! Check ${LOG} for errors." 6 60; return 1)
    return 0
}

# Set PACKAGES parameter before running to install wanted packages
run_pacman(){
    # create chroot environment on target system
    # code straight from mkarchroot
    chroot_mount
    DIALOG --infobox "Please be patient. Installing packages ..." 3 50
    echo "Installing Packages..." >/tmp/pacman.log
    #shellcheck disable=SC2086,SC2069
    ${PACMAN} -S ${PACKAGES} |& tee -a "${LOG}" /tmp/pacman.log >/dev/null 2>&1
    echo $? > /tmp/.pacman-retcode
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
    else
        echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
    fi
    # pacman finished, display scrollable output
    local _result=''
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        _result="Installation Failed (see errors below)"
        DIALOG --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/pacman.log" 18 70 || return 1
    else
        DIALOG --msgbox "Package installation complete." 5 40
    fi
    rm /tmp/.pacman-retcode
    # ensure the disk is synced
    sync
    chroot_umount
}

# install_packages()
# performs package installation to the target system
install_packages() {
    destdir_mounts || return 1
    if [[ "${S_SRC}" = "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman
    PACKAGES=""
    # add packages from archboot defaults
    PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${PACKAGES}" ]] && PACKAGES="base linux linux-firmware"
    auto_packages
    # fix double spaces
    PACKAGES="${PACKAGES//  / }"
    DIALOG --yesno "For a minimal system next step will install:\n\n${PACKAGES}\n\nYou can watch the progress on ${LOG}.\n\nDo you wish to continue?" 14 60 || return 1
    run_pacman
    NEXTITEM="6"
    chroot_mount
    # automagic time!
    # any automatic configuration should go here
    DIALOG --infobox "Writing base configuration..." 6 40
    auto_fstab
    auto_ssd
    auto_mdadm
    auto_luks
    auto_pacman
    auto_testing
    # tear down the chroot environment
    chroot_umount
}
