#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /etc/archboot/server-update.conf
[[ -d "${_ISO_HOME_CHROOTS}" ]] || mkdir -p "${_ISO_HOME_CHROOTS}"
cd "${_ISO_HOME_CHROOTS}"
# stop if MASK is set
[[ -e MASK ]] && exit 0
for i in ${_SERVER_ARCH}; do
    #  create container
    if ! [[ -d "${i}" ]]; then
        archboot-"${i}"-create-container.sh "${i}" -cp || exit 1
        rm "${i}"/var/log/pacman.log
    fi
    # update container to latest packages
    systemd-nspawn -q -D "${i}" pacman --noconfirm -Syu
    for k in ${_TRIGGER}; do
        # if trigger successful, release new image to server
        if rg -qw "${k}" "${i}"/var/log/pacman.log; then
            archboot-"${i}"-server-release.sh || echo "Error: ${i} release!" >> error.log
            break
        fi
    done
    rm "${i}"/var/log/pacman.log
done
# vim: set ft=sh ts=4 sw=4 et:
