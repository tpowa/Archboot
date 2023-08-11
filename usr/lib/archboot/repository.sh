#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_GPG_KEY="/usr/share/archboot/gpg/tpowa.gpg"

_usage () {
    echo "CREATE ARCHBOOT REPOSITORY"
    echo "--------------------------"
    echo "This will create an archboot repository for an archboot image."
    echo ""
    echo "usage: ${_BASENAME} <directory>"
    exit 0
}

_download_packages() {
    if [[ "${2}" == "use_binfmt" ]]; then
        _pacman_key "${1}"
    else
        _pacman_key_system
    fi
    _PACKAGES="${_PACKAGES} ${_ARCHBOOT} ${_KEYRING} ${_MAN_INFO_PACKAGES}"
    echo "Downloading ${_PACKAGES} to ${1}..."
    #shellcheck disable=SC2086
    ${_PACMAN} -Syw ${_PACKAGES} ${_PACMAN_DEFAULTS} ${_PACMAN_DB} &>/dev/null || exit 1
}

_move_packages() {
    echo "Moving packages to ${2}..."
    mv "${1}${_CACHEDIR}"/./* "${2}"
}

_cleanup_repodir() {
    echo "Removing ${1}..."
    rm -r "${1}"
}

# vim: set ft=sh ts=4 sw=4 et:
