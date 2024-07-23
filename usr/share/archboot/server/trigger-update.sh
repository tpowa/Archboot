#!/bin/bash
_ARCH="x86_64 aarch64 riscv64"
_PACKAGES="archboot bcachefs-tools btrfs-progs e2fsprogs glibc linux systemd openssh ttyd xfsprogs"
_CHROOTS="/home/tobias/Arch/iso/chroots"
cd "${_CHROOTS}" || exit 1
for i in ${_ARCH}; do
    systemd-nspawn -q -D "${i}" pacman --noconfirm -Syu
    for k in ${_PACKAGES}; do
        if rg -qw "${k}" "${i}"/var/log/pacman.log; then
            archboot-"${i}"-server-release.sh
            break
        fi
    done
    rm "${i}"/var/log/pacman.log
done
# vim: set ft=sh ts=4 sw=4 et:
