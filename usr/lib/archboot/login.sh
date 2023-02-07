#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# don't run ttyS0 as first device

_welcome () {
    [[ "$(uname -m)" == "x86_64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[0m\e[1m - Arch Linux\e[0m"
    [[ "$(uname -m)" == "aarch64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[0m\e[1m - Arch Linux ARM\e[0m"
    [[ "$(uname -m)" == "riscv64" ]] && echo -e "\e[1mWelcome to \e[36mArchboot\e[0m\e[1m - Arch Linux RISC-V 64\e[0m"
    echo -e "\e[1m--------------------------------------------------------------------\e[0m"
    _local_mode
}

_local_mode () {
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "You are running in \e[92m\e[1mLocal mode\e[0m, with \e[1mlocal package repository\e[0m enabled.\e[0m"
        if [[ -e /usr/bin/setup ]] ; then
            echo -e "To \e[1mswitch\e[0m to \e[1mOnline mode\e[0m:\e[1m\e[91m# rm /var/cache/pacman/pkg/archboot.db\e[0m\e[1m"
            echo ""
        fi
    fi
}

_enter_shell() {
    # dbus sources profiles again
    if ! pgrep -x dbus-run-sessio &>/dev/null; then
        cd /
        echo -e "Hit \e[1m\e[92mENTER\e[0m for \e[1mshell\e[0m login."
        read -r
        clear
    fi
}

_run_latest() {
    echo -e "\e[1mStarting\e[0m assembling of archboot environment \e[1mwithout\e[0m package cache..."
    echo -e "\e[1mRunning now: \e[92mupdate-installer -latest\e[0m"
    update-installer -latest | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_latest_install() {
    echo -e "\e[1mStarting\e[0m assembling of archboot environment \e[1mwith\e[0m package cache..."
    echo -e "\e[1mRunning now: \e[92mupdate-installer -latest-install\e[0m"
    update-installer -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/0 2>/dev/null
}

_run_update_installer() {
    [[ -z $TTY ]] && TTY=$(tty)
    TTY=${TTY#/dev/}
    cd /
    echo -e "\e[1m\e[92mMemory checks run successfully:\e[0m"
    echo -e "\e[93mGo and get a cup of coffee. Depending on your system setup,\e[0m"
    echo -e "\e[93myou can \e[1mstart\e[0m\e[93m with your tasks in about \e[1m5\e[0m\e[93m minutes...\e[0m"
    echo ""
    if [[ "${TTY}" == "tty1" ]]; then
        echo -e "\e[1m\e[91m10 seconds\e[0;25m time to hit \e[1m\e[92mCTRL-C\e[0m to \e[1m\e[91mstop\e[0m the process \e[1m\e[1mnow...\e[0m"
        sleep 10
        echo ""
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 ]]; then
            _run_latest
        else
            _run_latest_install
        fi
    elif [[ "${TTY}" == "ttyS0" || "${TTY}" == "ttyAMA0" || "${TTY}" == "ttyUSB0" || "${TTY}" == "pts/0" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 ]]; then
            echo -e "Running \e[1m\e[92mupdate-installer -latest-install\e[0m on \e[1mtty1\e[0m, please wait...\e[0m"
        else
            echo -e "\e[1mRunning now: \e[92mupdate-installer -latest\e[0m"
        fi
        echo -e "\e[1mProgress is shown here...\e[0m"
    fi
}

if ! [[ -e "/.vconsole-run" ]]; then
    touch /.vconsole-run
    FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" | sed -e 's#.*:##g')"
    if [[ "${FB_SIZE}" -gt '1900' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    echo KEYMAP=us > /etc/vconsole.conf
    echo FONT=ter-v${SIZE}n >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
fi
if ! [[ -e "/.clean-pacman-db" ]]; then
    touch /.clean-pacman-db
    _RM_PACMAN_DB="grub libxml2 icu gettext refind amd-ucode intel-ucode edk2-shell cdrtools \
        libisoburn libburn libisofs mkinitcpio memtest linux-api-headers jansson libwbclient \
        libbsd libmd libpcap libnftnl libnfnetlink libnetfilter_conntrack libsasl libldap mtools \
        libsysprof-capture libnsl libksba gdbm binutils"
    for i in ${_RM_PACMAN_DB}; do
        rm -rf /var/lib/pacman/local/${i}* &>/dev/null
    done
fi

if [[ -e /usr/bin/setup ]]; then
    _local_mode
    _enter_shell
    if ! [[ -e /tmp/.setup ]]; then
        setup
    fi
# latest image, fail if less than 2GB RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 1970000 ]]; then
    _welcome
    echo -e "\e[1m\e[91mMemory check failed:\e[0m"
    echo -e "\e[91m- Not engough memory detected! \e[0m"
    echo -e "\e[93m- Please add \e[1mmore\e[0m\e[93m than \e[1m2.0GB\e[0m\e[93m RAM.\e[0m"
    echo -e "\e[91mAborting...\e[0m"
    _enter_shell
# local image, fail if less than 2.6GB  RAM available
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 2571000 &&\
-e "/var/cache/pacman/pkg/archboot.db" ]]; then
    _welcome
    echo -e "\e[1m\e[91mMemory check failed:\e[0m"
    echo -e "\e[91m- Not engough memory detected! \e[0m"
    echo -e "\e[93m- Please add \e[1mmore\e[0m\e[93m than \e[1m2.6GB\e[0m\e[93m RAM.\e[0m"
    echo -e "\e[91mAborting...\e[0m"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
# vim: set ft=sh ts=4 sw=4 et:
