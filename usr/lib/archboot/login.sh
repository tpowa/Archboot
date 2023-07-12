#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh

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
        if [[ -e /usr/bin/setup ]] ; then
            # bring down network
            systemctl stop systemd-networkd 2>/dev/null
            systemctl stop systemd-resolved 2>/dev/null
            echo -e "To \e[1mswitch\e[m to \e[1mOnline Mode\e[m:\e[1m\e[91m# rm ${_CACHEDIR}/archboot.db\e[m\e[1m"
            echo ""
        fi
    fi
}

# use -o discard for RAM cleaning on delete
# (online fstrimming the block device!)
# fstrim <mountpoint> for manual action
# it needs some seconds to get RAM free on delete!
_switch_root_zram() {
[[ -z $TTY ]] && TTY=$(tty)
TTY=${TTY#/dev/}
if [[ "${TTY}" = "tty1" ]]; then
    clear
    echo -e "\e[1mInitializing\e[m \e[96mArchboot\e[m \e[1m- Arch Linux Environment:\e[m"
    echo -e "\e[1mStep 1/4:\e[m Creating /dev/zram0 with zstd compression..."
    [[ -d /sysroot ]] || mkdir /sysroot
    modprobe zram &>/dev/null
    modprobe zstd &>/dev/null
    echo "1" >/sys/block/zram0/reset
    echo "zstd" >/sys/block/zram0/comp_algorithm
    echo "4G" >/sys/block/zram0/disksize
    echo -e "\e[1mStep 2/4:\e[m Creating btrfs on /dev/zram0..."
    mkfs.btrfs /dev/zram0 &>/dev/null
    mount -o discard /dev/zram0 /sysroot &>/dev/null
    echo -e "\e[1mStep 3/4:\e[m Removing firmware and modules..."
    # cleanup firmware and modules
    mv /lib/firmware/regulatory* /tmp/
    rm -rf /lib/firmware/*
    mv /tmp/regulatory* /lib/firmware/
    rm -rf /lib/modules/*/kernel/drivers/{acpi,ata,gpu,bcma,block,bluetooth,hid,input,platform,net,scsi,soc,spi,usb,video}
    rm -rf /lib/modules/*/extramodules
    echo -e "\e[1mStep 4/4:\e[m Copying archboot rootfs to /sysroot..."
    tar -C / --exclude="./dev/*" --exclude="./proc/*" --exclude="./sys/*" \
        --exclude="./run/*" --exclude="./mnt/*" --exclude="./tmp/*" --exclude="./sysroot/*" \
        -clpf - . | tar -C /sysroot -xlspf - &>/dev/null
    # cleanup mkinitcpio directories and files
    rm -rf /sysroot/{hooks,install,kernel,new_root,sysroot} &>/dev/null
    rm -f /sysroot/{VERSION,config,buildconfig,init} &>/dev/null
    # systemd needs this for root_switch
    touch /etc/initrd-release
    echo -e "\e[1;96mArchboot\e[m \e[1m- Arch Linux Environment finished.\e[m"
    echo -e "\e[1mSystemd initrd-switch-root will be launched in a second...\e[m"
    read -r -t 3
    # https://www.freedesktop.org/software/systemd/man/bootup.html
    # enable systemd  initrd functionality
    touch /etc/initrd-release
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
    [[ -z $TTY ]] && TTY=$(tty)
    # dbus sources profiles again
    if ! echo "${TTY}" | grep -q pts; then
        echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mlogin\e[m routine."
        cd /
        read -r
        clear
    fi
}

_run_latest() {
    echo -e "\e[1mStarting\e[m assembling of archboot environment \e[1mwithout\e[m package cache..."
    echo -e "\e[1mRunning now: \e[92mupdate -latest\e[m"
    update -latest | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_latest_install() {
    echo -e "\e[1mStarting\e[m assembling of archboot environment \e[1mwith\e[m package cache..."
    echo -e "\e[1mRunning now: \e[92mupdate -latest-install\e[m"
    update -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_update_installer() {
    [[ -z $TTY ]] && TTY=$(tty)
    TTY=${TTY#/dev/}
    cd /
    echo -e "\e[1m\e[92mMemory checks run successfully:\e[m"
    echo -e "\e[93mGo and get a cup of coffee. Depending on your system setup,\e[m"
    echo -e "\e[93myou can \e[1mstart\e[m\e[93m with your tasks in about \e[1m5\e[m\e[93m minutes...\e[m"
    echo ""
    if [[ "${TTY}" == "tty1" ]]; then
        echo -e "\e[1m\e[91m10 seconds\e[0;25m time to hit \e[1m\e[92mCTRL-C\e[m to \e[1m\e[91mstop\e[m the process \e[1m\e[1mnow...\e[m"
        sleep 10
        echo ""
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
    elif [[ "${TTY}" == "ttyS0" || "${TTY}" == "ttyAMA0" || "${TTY}" == "ttyUSB0" || "${TTY}" == "pts/0" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 ]]; then
            echo -e "Running \e[1m\e[92mupdate -latest-install\e[m on \e[1mtty1\e[m, please wait...\e[m"
        else
            echo -e "\e[1mRunning now: \e[92mupdate -latest\e[m"
        fi
        echo -e "\e[1mProgress is shown here...\e[m"
    fi
}

if ! [[ -e /.vconsole-run ]]; then
    touch /.vconsole-run
    FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" | sed -e 's#.*:##g')"
    if [[ "${FB_SIZE}" -gt '1900' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    echo KEYMAP=us >/etc/vconsole.conf
    echo FONT=ter-v${SIZE}n >>/etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
fi
if ! [[ -e /.clean-pacman-db ]]; then
    touch /.clean-pacman-db
    _RM_PACMAN_DB="base grub libxml2 icu gettext refind amd-ucode intel-ucode edk2-shell \
        libisoburn libburn libisofs mkinitcpio memtest linux-api-headers jansson libwbclient \
        libbsd libmd libpcap libnftnl libnfnetlink libnetfilter_conntrack libsasl libldap memtest86+ \
        memtest86+-efi mkinitcpio-busybox mtools libsysprof-capture libnsl libksba gdbm binutils \
        cdrtools systemd-ukify python python-pefile"
    for i in ${_RM_PACMAN_DB}; do
        rm -rf /var/lib/pacman/local/"${i}"-[0-9]* &>/dev/null
    done
fi

if ! mount | grep -q zram0; then
    _switch_root_zram | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
else
    systemctl start systemd-networkd
    systemctl start systemd-resolved
    # initialize pacman keyring
    if [[ -e /etc/systemd/system/pacman-init.service ]]; then
        systemctl start pacman-init
    fi
fi

if [[ -e /usr/bin/setup ]]; then
    _local_mode
    # wait on user interaction!
    _enter_shell
    # basic environment setup:
    # glibc locale, vconsole, network, clock
    if ! [[ -e /tmp/.locale ]]; then
        archboot-locale.sh
        source /etc/locale.conf
    fi
    if ! [[ -e /tmp/.keymap ]]; then
        km && : >/tmp/.keymap
    fi
    if [[ ! -e /tmp/.network && ! -e "${_CACHEDIR}/archboot.db" ]]; then
        network && : >/tmp/.network
    fi
    if ! [[ -e /tmp/.timezone ]]; then
        tz && : >/tmp/.timezone
    fi
    # switch for setup or launcher
    if [[ ! -e /tmp/.setup && -e "${_CACHEDIR}/archboot.db" ]]; then
        # run setup on local medium once!
        setup
    else
        # run launcher on latest/normal medium once!
        if [[ ! -e /tmp/.launcher ]]; then
            launcher
        fi
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
