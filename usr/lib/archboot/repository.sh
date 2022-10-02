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

_cachedir_check() {
    if grep -q ^CacheDir /etc/pacman.conf; then
        echo "Error: CacheDir set in /etc/pacman.conf. Aborting ..."
        exit 1
    fi
}

_download_packages() {
    _PACMAN_OPTIONS="${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} ${_PACMAN_DEFAULTS}"
    if [[ "${2}" == "use_binfmt" ]]; then
        _PACMAN_DB=""
        mkdir "${1}"/blankdb
        echo "Adding ${_GPG_KEY_ID} to trusted keys"
        [[ -d "${1}"/usr/share/archboot/gpg ]] || mkdir -p "${1}"/usr/share/archboot/gpg
        cp "${_GPG_KEY}" "${1}"/"${_GPG_KEY}"
        ${_NSPAWN} pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
        ${_NSPAWN} pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
        # riscv64 does not support local image at the moment
        _CONTAINER_ARCH="$(${_NSPAWN} uname -m)"
        #shellcheck disable=SC2001
        [[ "$(echo "${_CONTAINER_ARCH}" | sed -e 's#\r##g')" == "riscv64" ]] && _GRAPHICAL_PACKAGES=""
    else
        _PACMAN_DB="--dbpath ${1}/blankdb"
        echo "Adding ${_GPG_KEY_ID} to trusted keys"
        pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
        pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    fi
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

