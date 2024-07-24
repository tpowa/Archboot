#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="x86_64 aarch64 riscv64"
_TRIGGER="archboot bcachefs-tools btrfs-progs cryptsetup device-mapper dosfstools e2fsprogs glibc linux linux-firmware lvm2 mdadm systemd thin-provisioning-tools openssh ttyd xfsprogs"
_CHROOTS="/home/tobias/Arch/iso/chroots"
cd "${_CHROOTS}" || exit 1
for i in ${_ARCH}; do
    systemd-nspawn -q -D "${i}" pacman --noconfirm -Syu
    for k in ${_TRIGGER}; do
        if rg -qw "${k}" "${i}"/var/log/pacman.log; then
            archboot-"${i}"-server-release.sh
            break
        fi
    done
    rm "${i}"/var/log/pacman.log
done
# vim: set ft=sh ts=4 sw=4 et:
