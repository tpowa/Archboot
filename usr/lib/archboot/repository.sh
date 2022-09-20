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
    echo "Adding ${_GPG_KEY_ID} to trusted keys"
    pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
    pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    echo "Downloading packages ${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
    #shellcheck disable=SC2086
    pacman --root "${1}" -Syw ${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --ignore systemd-resolvconf --noconfirm --cachedir "${_CACHEDIR}" >/dev/null 2>&1
}

_other_download_packages() {
    mkdir "${1}"/blankdb
    echo "Adding ${_GPG_KEY_ID} to trusted keys"
    [[ -d "${1}"/usr/share/archboot/gpg ]] || mkdir -p "${1}"/usr/share/archboot/gpg
    cp "${_GPG_KEY}" "${1}"/"${_GPG_KEY}"
    systemd-nspawn -q -D "${1}" pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    # riscv64 does not support local image at the moment
    [[ "$(echo $(systemd-nspawn -q -D "${1}" uname -m) | sed -e 's#\r##g')" == "riscv64" ]] && _GRAPHICAL_PACKAGES=""
    echo "Downloading packages ${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw ${_PACKAGES} ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --dbpath /blankdb --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
}

_move_packages() {
    echo "Moving packages to ${2} ..."
    mv "${1}"/var/cache/pacman/pkg/./* "${2}"
}

_cleanup_repodir() {
    echo "Remove ${1}  ..."
    rm -r "${1}"
}

