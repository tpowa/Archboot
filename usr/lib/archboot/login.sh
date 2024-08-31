#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
[[ -z $_TTY ]] && _TTY=$(tty)
_TTY=${_TTY#/dev/}

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
if [[ "${_TTY}" = "tty1" ]]; then
    clear
    [[ -d /run/nextroot ]] || mkdir /run/nextroot
    : > /.archboot
    _create_btrfs &
    _progress_wait "0" "99" "Creating btrfs on /dev/zram0..." "0.05"
    # avoid clipping, insert status message
    _progress "100" "Creating btrfs on /dev/zram0..."
    : > /.archboot
    _copy_root &
    _progress_wait "0" "99" "Copying rootfs to /run/nextroot..." "0.05"
    # cleanup directories and files
    rm -r /run/nextroot/sysroot &>"${_NO_LOG}"
    rm /run/nextroot/sysroot/init &>"${_NO_LOG}"
    _progress "100" "System is ready."
else
    while true; do
        sleep 1
    done
fi
}

_enter_shell() {
    # dbus sources profiles again
    if ! echo "${_TTY}" | rg -q 'pts'; then
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
    if [[ "${_TTY}" == "tty1" ]]; then
        if [[ "${_MEM_TOTAL}" -lt 2971000 ]]; then
            _run_latest
        else
            # local image
            if [[ -e "${_LOCAL_DB}" ]]; then
                _run_latest_install
            else
                # latest image
                if update | rg -q 'latest-install'; then
                    _run_latest_install
                else
                    _run_latest
                fi
            fi
        fi
    fi
}

_run_autorun() {
    # check on cmdline, don't run on local image, only run autorun once!
    if rg -q 'autorun=' /proc/cmdline && [[ ! -e "${_LOCAL_DB}" ]]; then
        : > /.autorun
        _REMOTE_AUTORUN="$(rg -o 'autorun=(.*)' -r '$1' /proc/cmdline | sd ' .*' '')"
        echo "Trying 30 seconds to download:"
        echo -n "${_REMOTE_AUTORUN} --> autorun.sh..."
        [[ -d /etc/archboot/run ]] || mkdir -p /etc/archboot/run
        _COUNT=""
        while true; do
            sleep 1
            if ${_DLPROG} -o /etc/archboot/run/autorun.sh "${_REMOTE_AUTORUN}"; then
                echo -e "\e[1;94m => \e[1;92mSuccess.\e[m"
                break
            fi
            _COUNT=$((_COUNT+1))
            if [[ "${_COUNT}" == 30 ]]; then
                echo -e "\e[1;94m => \e[1;91mERROR: Download failed.\e[m"
                sleep 5
                break
            fi
        done
    fi
    if [[ -f /etc/archboot/run/autorun.sh ]]; then
        echo "Waiting for pacman keyring..."
        _pacman_keyring
        echo "Updating pacman keyring..."
        pacman -Sy --noconfirm ${_KEYRING} &>"${_LOG}"
        chmod 755 /etc/archboot/run/autorun.sh
        echo "Running custom autorun.sh..."
        /etc/archboot/run/./autorun.sh
        echo "Finished autorun.sh."
    fi
}

if [[ "${_TTY}" = "tty1" ]] ; then
    if ! mount | rg -q 'zram0'; then
        _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | ZRAM"
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
    ! [[ -e /.autorun ]] && _run_autorun
fi
# start bottom on VC6
while [[ "${_TTY}" = "tty6" ]] ; do
    if command -v btm &>"${_NO_LOG}"; then
        btm --battery
    else
        break
    fi
done
# start bandwhich on VC5 on online medium
while [[ "${_TTY}" = "tty5" && ! -e "${_LOCAL_DB}" ]] ; do
    if command -v bandwhich &>"${_NO_LOG}"; then
        bandwhich
    else
        break
    fi
done
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
# latest image, fail if less than 2.3GB RAM available
elif [[ "${_MEM_TOTAL}" -lt 2270000 ]]; then
    _welcome
    _memory_error "2.3GB"
    _enter_shell
# local image, fail if less than 3.0GB  RAM available
elif [[ "${_MEM_TOTAL}" -lt 2971000 &&\
-e "${_LOCAL_DB}" ]]; then
    _welcome
    _memory_error "2.9GB"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
