#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_GPG_KEY="/usr/share/archboot/gpg/tpowa.gpg"

_usage () {
    echo "CREATE ARCHBOOT REPOSITORY"
    echo "-----------------------------"
    echo "This will create an archboot repository for an archboot image."
    echo "Usage: ${_BASENAME} <directory>"
    exit 0
}

_download_packages() {
    if [[ "${2}" == "use_binfmt" ]]; then
        _copy_gpg_key "${1}"
        _riscv64_disable_graphics "${1}"
    fi
    _PACMAN_OPTIONS="${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} ${_PACMAN_DEFAULTS}"
    _pacman_key
    echo "Downloading packages ${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
    ${_PACMAN} -Syw ${_PACMAN_OPTIONS} ${_PACMAN_DB} >/dev/null 2>&1 || exit 1
}

_move_packages() {
    echo "Moving packages to ${2} ..."
    mv "${1}"/var/cache/pacman/pkg/./* "${2}"
}

_cleanup_repodir() {
    echo "Remove ${1}  ..."
    rm -r "${1}"
}

