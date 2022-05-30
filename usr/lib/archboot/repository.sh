#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults

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
    echo "Downloading packages ${_PACKAGES} ${_ARCHBOOT} ${_XORG} to ${1} ..."
    pacman-key -r 771DF6627EDF681F --keyserver hkp://keyserver.ubuntu.com
    #shellcheck disable=SC2086
    pacman --root "${1}" -Syw ${_PACKAGES} ${_ARCHBOOT} ${_XORG} --ignore systemd-resolvconf --noconfirm --cachedir "${_CACHEDIR}" >/dev/null 2>&1
}

_aarch64_download_packages() {
    mkdir "${1}"/blankdb
    systemd-nspawn -q -D "${1}" pacman-key -r 771DF6627EDF681F --keyserver hkp://keyserver.ubuntu.com
    echo "Downloading packages ${_PACKAGES} ${_ARCHBOOT} ${_XORG} to ${1} ..."
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw ${_PACKAGES} ${_ARCHBOOT} ${_XORG} --dbpath /blankdb --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
}

_move_packages() {
    echo "Moving packages to ${2} ..."
    mv "${1}"/var/cache/pacman/pkg/./* "${2}"
}

_cleanup_repodir() {
    echo "Remove ${1}  ..."
    rm -r "${1}"
}

