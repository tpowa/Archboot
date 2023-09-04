#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
[[ -z $TTY ]] && TTY=$(tty)
TTY=${TTY#/dev/}

_welcome () {
    [[ "$(uname -m)" == "x86_64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[m\e[1m - Arch Linux X86_64\e[m"
    [[ "$(uname -m)" == "aarch64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[m\e[1m - Arch Linux AARCH64\e[m"
    [[ "$(uname -m)" == "riscv64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[m\e[1m - Arch Linux RISCV64\e[m"
    echo -e "\e[1m--------------------------------------------------------------------\e[m"
    _local_mode
}

_local_mode () {
    if [[ -e "${_CACHEDIR}/archboot.db" ]]; then
        echo -e "You are running in \e[92m\e[1mOffline Mode\e[m, with \e[1mlocal package repository\e[m enabled.\e[m"
    fi
}

# use -o discard for RAM cleaning on delete
# (online fstrimming the block device!)
# fstrim <mountpoint> for manual action
# it needs some seconds to get RAM free on delete!
_switch_root_zram() {
if [[ "${TTY}" = "tty1" ]]; then
    clear
    [[ -d /sysroot ]] || mkdir /sysroot
    modprobe zram &>"${_NO_LOG}"
    modprobe zstd &>"${_NO_LOG}"
    echo "1" >/sys/block/zram0/reset
    echo "zstd" >/sys/block/zram0/comp_algorithm
    echo "5G" >/sys/block/zram0/disksize
    _progress "1" "Creating btrfs on /dev/zram0..."
    mkfs.btrfs /dev/zram0 &>"${_NO_LOG}"
    mount -o discard /dev/zram0 /sysroot &>"${_NO_LOG}"
    _progress "3" "Removing firmware and modules..."
    # cleanup firmware and modules
    mv /lib/firmware/regulatory* /tmp/
    rm -rf /lib/firmware/*
    mv /tmp/regulatory* /lib/firmware/
    rm -rf /lib/modules/*/kernel/drivers/{acpi,ata,gpu,bcma,block,bluetooth,hid,input,platform,net,scsi,soc,spi,usb,video}
    rm -rf /lib/modules/*/extramodules
    : > /.archboot
    (tar -C / --exclude="./dev/*" --exclude="./proc/*" --exclude="./sys/*" \
        --exclude="./run/*" --exclude="./mnt/*" --exclude="./tmp/*" --exclude="./sysroot/*" \
        -clpf - . | tar -C /sysroot -xlspf - &>"${_NO_LOG}"; rm /.archboot) &
    _progress_wait "4" "99" "Copying archboot rootfs to /sysroot..." "0.125"
    # cleanup mkinitcpio directories and files
    rm -rf /sysroot/{hooks,install,kernel,new_root,sysroot} &>"${_NO_LOG}"
    rm -f /sysroot/{VERSION,config,buildconfig,init,.archboot} &>"${_NO_LOG}"
    _progress "100" "System is ready."
    read -r -t 1
    # fix clear screen on all terminals
    printf "\ec" | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
    # https://www.freedesktop.org/software/systemd/man/bootup.html
    # enable systemd  initrd functionality
    : > /etc/initrd-release
    # fix /run/nouser issues
    systemctl stop systemd-user-sessions.service
    # avoid issues by taking down services in ordered way
    systemctl stop dbus-org.freedesktop.login1.service
    systemctl stop dbus.socket
    # prepare for initrd-switch-root
    systemctl start initrd-cleanup.service
    systemctl start initrd-switch-root.target
else
    while true; do
        read -r -t 1
    done
fi
}

_enter_shell() {
    # dbus sources profiles again
    if ! echo "${TTY}" | grep -q pts; then
        echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mlogin\e[m routine."
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
            if [[ -e "${_CACHEDIR}/archboot.db" ]]; then
                _run_latest_install
            else
                # latest image
                if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 3271000 ]]; then
                    _run_latest
                else
                    _run_latest_install
                fi
            fi
        fi
    fi
}

if ! [[ -e /.vconsole-run ]]; then
    : > /.vconsole-run
    FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" 2>"${_NO_LOG}" | sed -e 's#.*:##g')"
    if [[ "${FB_SIZE}" -gt '1900' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    echo KEYMAP=us >/etc/vconsole.conf
    echo FONT=ter-v${SIZE}n >>/etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
fi

if [[ "${TTY}" = "tty1" ]] ; then
    if ! mount | grep -q zram0; then
        _TITLE="Archboot $(uname -m) | Basic Setup | ZRAM"
        _switch_root_zram | _dialog --title " Initializing System " --gauge "Creating /dev/zram0 with zstd compression..." 6 75 0 | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>"${_NO_LOG}"
    else
        if ! [[ -e "${_CACHEDIR}/archboot.db" ]]; then
            systemctl start systemd-networkd
            systemctl start systemd-resolved
        fi
        # initialize pacman keyring
        if [[ -e /etc/systemd/system/pacman-init.service ]]; then
            systemctl start pacman-init
        fi
    fi
fi
# enable super keys console support
loadkeys windowkeys
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
    if [[ ! -e /.network ]]; then
        network
    fi
    if ! [[ -e /.clock ]]; then
        clock
    fi
    if [[ ! -e /.pacsetup ]]; then
        pacsetup
    fi
    if [[ ! -e /.launcher ]]; then
        launcher
    fi
# latest image, fail if less than 2GB RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 1970000 ]]; then
    _welcome
    echo -e "\e[1m\e[91mMemory check failed:\e[m"
    echo -e "\e[91m- Not engough memory detected! \e[m"
    echo -e "\e[93m- Please add \e[1mmore\e[m\e[93m than \e[1m2.0GB\e[m\e[93m RAM.\e[m"
    echo -e "\e[91mAborting...\e[m"
    _enter_shell
# local image, fail if less than 3.3GB  RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 &&\
-e "${_CACHEDIR}/archboot.db" ]]; then
    _welcome
    echo -e "\e[1m\e[91mMemory check failed:\e[m"
    echo -e "\e[91m- Not engough memory detected! \e[m"
    echo -e "\e[93m- Please add \e[1mmore\e[m\e[93m than \e[1m2.6GB\e[m\e[93m RAM.\e[m"
    echo -e "\e[91mAborting...\e[m"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
# vim: set ft=sh ts=4 sw=4 et:
