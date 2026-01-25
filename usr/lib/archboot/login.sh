#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
[[ -z $_TTY ]] && _TTY=$(tty)
_TTY=${_TTY#/dev/}

_welcome () {
    echo -e "\e[1mWelcome to \e[36mArchboot\e[m\e[1m - Arch Linux ${_RUNNING_ARCH^^}\e[m"
    echo -e "\e[1m----------------------------------------------------------------\e[m"
    _local_mode
}

_local_mode () {
    if [[ -e "${_LOCAL_DB}" ]]; then
        echo -e "\e[92m\e[1mOffline Mode\e[m, with \e[1mlocal package repository\e[m is enabled.\e[m"
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
    echo "zstd" >/sys/block/zram0/comp_algorithm
    echo "6G" >/sys/block/zram0/disksize
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
if [[ "${_TTY}" = "pts/0" ]]; then
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
    if ! [[ -e /.shell ]]; then
        echo ""
        echo -e "Hit \e[1m\e[92mENTER\e[m for \e[1mlogin\e[m routine or \e[1m\e[92mCTRL-C\e[m for \e[1mbash\e[m prompt."
        cd /
        read -r && : > /.shell
        clear
    fi
}

_run_update_installer() {
    cd /
    if [[ "${_TTY}" == "pts/0" ]]; then
        if update | rg -q 'latest-install'; then
            update -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/1 2>"${_NO_LOG}"
        else
            update -latest | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/1 2>"${_NO_LOG}"
        fi
    fi
}

_run_autorun() {
    # check on cmdline parameter, don't run on local image
    if rg -q 'autorun=' /proc/cmdline && [[ ! -e "${_LOCAL_DB}" ]]; then
        : > /.autorun
        clear
        _REMOTE_AUTORUN="$(rg -o 'autorun=(.*)' -r '$1' /proc/cmdline | sd ' .*' '')"
        echo "Trying 30 seconds to download:"
        echo -n "${_REMOTE_AUTORUN} --> autorun.sh..."
        [[ -d /etc/archboot/run ]] || mkdir -p /etc/archboot/run
        if ${_DLPROG} --max-time 30 -o /etc/archboot/run/autorun.sh "${_REMOTE_AUTORUN}"; then
                echo -e "\e[1;94m => \e[1;92mSuccess.\e[m"
        else
                echo -e "\e[1;94m => \e[1;91mERROR: Download failed.\e[m"
        fi
    fi
    if [[ -f /etc/archboot/run/autorun.sh ]]; then
        # don't run on pre environment
        if [[ -e "${_LOCAL_DB}" ]] && ! [[ -e /.autorun ]]; then
            : > /.autorun
        else
            echo "Waiting for pacman keyring..."
            _pacman_keyring
            echo "Updating pacman keyring..."
            pacman -Sy --noconfirm "${_KEYRING[@]}" &>>"${_LOG}"
            chmod 755 /etc/archboot/run/autorun.sh
            echo "Running custom autorun.sh..."
            /etc/archboot/run/./autorun.sh
            echo "Finished autorun.sh."
            echo
            echo "Relogin on pts/0 in 5 seconds..."
            sleep 5
            exit
        fi
    fi
}
if [[ "${_TTY}" = "pts/0" ]] ; then
    _udev_trigger
    if ! mount | rg -q 'zram0'; then
        _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | ZRAM"
        _switch_root_zram | _dialog --title " Initializing System " --gauge "Creating btrfs on /dev/zram0..." 6 75 0 | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/1 2>"${_NO_LOG}"
        # fix clear screen on all terminals
        printf "\ec" | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 /dev/pts/1 2>"${_NO_LOG}"
        echo "Launching systemd $(udevadm --version)..."
        systemctl soft-reboot
    else
        if ! [[ -e "${_LOCAL_DB}" ]]; then
            systemctl start systemd-networkd
            systemctl start systemd-resolved
            systemctl start bandwhich-tty4.service
        fi
        # initialize pacman keyring
        [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl start pacman-init
    fi
    # only run autorun.sh once!
    ! [[ -e /.autorun ]] && _run_autorun
    systemctl start journal-tty9.service
    systemctl start btm-tty5.service
    : > /tmp/archboot.log
    systemctl start log-tty8.service
fi
if [[ -e /usr/bin/setup ]]; then
    if [[ "${_MEM_TOTAL}" -gt "${_MEM_LIMIT_BARE_MINIMUM}" ]]; then
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
        if [[ -e /.gnome-wayland ]]; then
            rm /.gnome-wayland
            gnome-wayland
        fi
    else
        _welcome
        _memory_error "${_MEM_LIMIT_BARE_MINIMUM}"
        _enter_shell
    fi
elif [[ "${_MEM_TOTAL}" -lt "${_MEM_LIMIT_LATEST}" ]]; then
    _welcome
    _memory_error "${_MEM_LIMIT_LATEST}"
    _enter_shell
elif [[ "${_MEM_TOTAL}" -lt "${_MEM_LIMIT_PACKAGE_CACHE}" &&\
-e "${_LOCAL_DB}" ]]; then
    _welcome
    _memory_error "${_MEM_LIMIT_PACKAGE_CACHE}"
    _enter_shell
else
    _welcome
    _run_update_installer
fi
