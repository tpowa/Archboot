#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
[[ -z $TTY ]] && TTY=$(tty)
TTY=${TTY#/dev/}

_welcome () {
    echo -e "\e[1mWelcome to \e[36mArchboot\e[m\e[1m - Arch Linux ${_RUNNING_ARCH^^}\e[m"
    echo -e "\e[1m--------------------------------------------------------------------\e[m"
    _local_mode
}

_local_mode () {
    if [[ -e "${_LOCAL_DB}" ]]; then
        echo -e "You are running in \e[92m\e[1mOffline Mode\e[m, with \e[1mlocal package repository\e[m enabled.\e[m"
    fi
}

_memory_error () {
    echo -e "\e[1m\e[91mMemory check failed:\e[m"
    echo -e "\e[91m- Not engough memory detected! \e[m"
    echo -e "\e[93m- Please add \e[1mmore\e[m\e[93m than \e[1m${1}\e[m\e[93m RAM.\e[m"
    echo -e "\e[91mAborting...\e[m"
}

_create_btrfs() {
    modprobe -q zram
    modprobe -q zstd
    echo "1" >/sys/block/zram0/reset
    echo "zstd" >/sys/block/zram0/comp_algorithm
    echo "5G" >/sys/block/zram0/disksize
    mkfs.btrfs /dev/zram0 &>"${_NO_LOG}"
    mount -o discard /dev/zram0 /run/nextroot
    rm /.archboot
}

_copy_root() {
    tar -C / --exclude="./dev/*" --exclude="./proc/*" --exclude="./sys/*" \
        --exclude="./run/*" --exclude="./mnt/*" --exclude="./tmp/*" --exclude="./sysroot/*" \
        -clpf - . | tar -C /run/nextroot -xlspf - &>"${_NO_LOG}"
    rm /.archboot
}

# use -o discard for RAM cleaning on delete
# (online fstrimming the block device!)
# fstrim <mountpoint> for manual action
# it needs some seconds to get RAM free on delete!
_switch_root_zram() {
if [[ "${TTY}" = "tty1" ]]; then
    clear
    [[ -d /run/nextroot ]] || mkdir /run/nextroot
    : > /.archboot
    _create_btrfs &
    _progress_wait "0" "5" "Creating btrfs on /dev/zram0..." "0.2"
    # avoid clipping, insert status message
    _progress "6" "Creating btrfs on /dev/zram0..."
    : > /.archboot
    _copy_root &
    _progress_wait "7" "99" "Copying rootfs to /run/nextroot..." "0.125"
    # cleanup directories and files
    rm -r /run/nextroot/sysroot &>"${_NO_LOG}"
    rm /run/nextroot/sysroot/init &>"${_NO_LOG}"
    _progress "100" "System is ready."
    read -r -t 1
else
    while true; do
        read -r -t 1
    done
fi
}

_enter_shell() {
    # dbus sources profiles again
    if ! echo "${TTY}" | grep -q pts; then
        echo ""
        echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mlogin\e[m routine or \e[1m\e[92mCTRL-C\e[m for \e[1mbash\e[m prompt."
        cd /
        read -r
        clear
    fi
}

_run_latest() {
    update -latest | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
}

_run_latest_install() {
    update -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
}

_run_update_installer() {
    cd /
    if [[ "${TTY}" == "tty1" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 ]]; then
            _run_latest
        else
            # local image
            if [[ -e "${_LOCAL_DB}" ]]; then
                _run_latest_install
            else
                # latest image
                if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4061000 ]]; then
                    _run_latest
                else
                    _run_latest_install
                fi
            fi
        fi
    fi
}

if [[ "${TTY}" = "tty1" ]] ; then
    if ! mount | grep -q zram0; then
        _TITLE="Archboot ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | ZRAM"
        _switch_root_zram | _dialog --title " Initializing System " --gauge "Creating btrfs on /dev/zram0..." 6 75 0 | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
        # fix clear screen on all terminals
        printf "\ec" | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
        echo "Launching systemd $(udevadm --version)..."
        systemctl soft-reboot
    else
        if ! [[ -e "${_LOCAL_DB}" ]]; then
            systemctl start systemd-networkd
            systemctl start systemd-resolved
        fi
        # initialize pacman keyring
        [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl start pacman-init
    fi
fi
if [[ -e /usr/bin/setup ]]; then
    _local_mode
    # wait on user interaction!
    _enter_shell
    # Basic Setup on archboot:
    # localization, network, clock, pacman
    if ! [[ -e /.localize ]]; then
        localize
        . /etc/locale.conf
    fi
    if ! [[ -e /.network ]]; then
        network
    fi
    if ! [[ -e /.clock ]]; then
        clock
    fi
    if ! [[ -e /.pacsetup ]]; then
        pacsetup
    fi
    if ! [[ -e /.launcher ]]; then
        launcher
    fi
# latest image, fail if less than 2GB RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 1970000 ]]; then
    _welcome
    _memory_error "2.0GB"
    _enter_shell
# local image, fail if less than 2.6GB  RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 &&\
-e "${_LOCAL_DB}" ]]; then
    _welcome
    _memory_error "2.6GB"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
# vim: set ft=sh ts=4 sw=4 et:
