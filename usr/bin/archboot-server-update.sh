#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /etc/archboot/server-update.conf
. /usr/lib/archboot/common.sh
_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Update Server To New Image\e[m"
    echo -e "\e[1m-------------------------------------\e[m"
    echo "Check on new packages and release new images to server."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_root_check
[[ -d "${_ISO_HOME_CONTAINERS}" ]] || mkdir -p "${_ISO_HOME_CONTAINERS}"
cd "${_ISO_HOME_CONTAINERS}" || exit 1
# stop if MASK is set
[[ -e MASK ]] && exit 0
_FIRST_RUN=1
for i in ${_SERVER_ARCH}; do
    [[ -z "${_FIRST_RUN}" ]] && sleep "${_SERVER_WAIT}"
    _FIRST_RUN=""
    #  create container
    if ! [[ -d "${i}" ]]; then
        archboot-"${i}"-create-container.sh "${i}" -cp || exit 1
        rm "${i}"/var/log/pacman.log
    fi
    # update container to latest packages
    systemd-nspawn -q -D "${i}" pacman --noconfirm -Syu
    rg -o 'upgraded (.*) \(' -r '$1' "${i}"/var/log/pacman.log > upgrade-"${i}".log
    #shellcheck disable=SC2068
    for k in ${_TRIGGER[@]}; do
        # if trigger successful, release new image to server
        if rg -qw "${k}" upgrade-"${i}".log; then
            archboot-"${i}"-server-release.sh run || echo "Error: ${i} release!" >> error.log
            break
        fi
    done
    rm upgrade-"${i}".log
    rm "${i}"/var/log/pacman.log
    rm "${i}"/var/cache/pacman/pkg/*
done
