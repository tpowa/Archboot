#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_GPG_KEY="/usr/share/archboot/gpg/tpowa.gpg"

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create Repository\e[m"
    echo -e "\e[1m----------------------------\e[m"
    echo "This will create an Archboot repository for an Archboot image."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <directory>\e[m"
    exit 0
}

_download_packages() {
    if [[ "${2}" == "use_binfmt" ]]; then
        _pacman_key "${1}"
    else
        _pacman_key_system
    fi
    #shellcheck disable=SC2206
    _PACKAGES+=(${_KEYRING[@]} ${_ARCHBOOT} ${_MAN_INFO_PACKAGES[@]})
    #shellcheck disable=SC2145
    echo "Downloading ${_PACKAGES[@]} to ${1}..."
    #shellcheck disable=SC2086,SC2068
    ${_PACMAN} -Syw ${_PACKAGES[@]} ${_PACMAN_DEFAULTS} ${_PACMAN_DB} &>"${_NO_LOG}" || exit 1
}

_move_packages() {
    echo "Moving packages to ${2}..."
    mv "${1}${_CACHEDIR}"/./* "${2}"
}

_cleanup_repodir() {
    echo "Removing ${1}..."
    rm -r "${1}"
}

