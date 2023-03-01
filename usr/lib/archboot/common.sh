#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_BASENAME="$(basename "${0}")"
_RUNNING_ARCH="$(uname -m)"
_KEYRING="archlinux-keyring"
if echo "${_BASENAME}" | grep -qw aarch64; then
    _ARCHBOOT="archboot-arm"
    _KEYRING="${_KEYRING} archlinuxarm-keyring"
    _ARCH="aarch64"
elif echo "${_BASENAME}" | grep -qw riscv64; then
    _ARCHBOOT="archboot-riscv"
    _ARCH="riscv64"
else
    _ARCHBOOT="archboot"
    _ARCH="x86_64"
fi
_PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
_PACMAN_CONF="/etc/pacman.conf"
_CACHEDIR="/var/cache/pacman/pkg"
_FIX_PACKAGES="libelf libevent talloc gcc-libs glibc glib2 pcre2"
_XORG_PACKAGE="xorg"
_VNC_PACKAGE="tigervnc"
_WAYLAND_PACKAGE="egl-wayland"
_STANDARD_PACKAGES="gparted nss-mdns"
# chromium is now working on riscv64
[[ "${_RUNNING_ARCH}" == "riscv64" ]] && _STANDARD_BROWSER="firefox"
_NSPAWN="systemd-nspawn -q -D"

### check for root
_root_check() {
    if ! [[ ${UID} -eq 0 ]]; then
        echo "ERROR: Please run as root user!"
        exit 1
    fi
}

### check for x86_64
_x86_64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        echo "ERROR: Pleae run on x86_64 hardware."
        exit 1
    fi
}

### check for aarch64
_aarch64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        echo "ERROR: Please run on aarch64 hardware."
        exit 1
    fi
}

### check for aarch64
_riscv64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo "ERROR: Please run on riscv64 hardware."
        exit 1
    fi
}

### check architecture
_architecture_check() {
    echo "${_BASENAME}" | grep -qw aarch64 && _aarch64_check
    echo "${_BASENAME}" | grep -qw riscv64 && _riscv64_check
    echo "${_BASENAME}" | grep -qw x86_64 && _x86_64_check
}

### check if running in container
_container_check() {
    if grep -q bash /proc/1/sched ; then
        echo "ERROR: Running inside container. Aborting..."
        exit 1
    fi
}

### check for tpowa's build server
_buildserver_check() {
    if [[ ! "$(cat /etc/hostname)" == "T-POWA-LX" ]]; then
        echo "This script should only be run on tpowa's build server. Aborting..."
        exit 1
    fi
}

_generate_keyring() {
    # use fresh one on normal systems
    # copy existing gpg cache on archboot usage
    if ! grep -qw archboot /etc/hostname; then
        # generate pacman keyring
        echo "Generating pacman keyring in container..."
        ${_NSPAWN} "${1}" pacman-key --init &>/dev/null
        ${_NSPAWN} "${1}" pacman-key --populate &>/dev/null
    else
        cp -ar /etc/pacman.d/gnupg "${1}"/etc/pacman.d &>/dev/null
    fi
}

_x86_64_pacman_use_default() {
    # use pacman.conf with disabled [testing] repository
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "Using system's ${_PACMAN_CONF}..."
    else
        echo "Copying ${_CUSTOM_PACMAN_CONF} to ${_PACMAN_CONF}..."
        cp "${_PACMAN_CONF}" "${_PACMAN_CONF}".old
        cp "${_CUSTOM_PACMAN_CONF}" "${_PACMAN_CONF}"
    fi
    # use mirrorlist with enabled rackspace mirror
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "Using system's ${_PACMAN_MIRROR}..."    
    else
        echo "Copying ${_CUSTOM_MIRRORLIST} to ${_PACMAN_MIRROR}..."
        cp "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}".old
        cp "${_CUSTOM_MIRRORLIST}" "${_PACMAN_MIRROR}"
    fi
}

_x86_64_pacman_restore() {
    # restore pacman.conf and mirrorlist
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "System's ${_PACMAN_CONF} used..."
    else
        echo "Restoring system's ${_PACMAN_CONF}..."
         cp "${_PACMAN_CONF}".old "${_PACMAN_CONF}"
    fi
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "System's ${_PACMAN_MIRROR} used..."
    else
        echo "Restoring system's ${_PACMAN_MIRROR}..."
        cp "${_PACMAN_MIRROR}".old "${_PACMAN_MIRROR}"
    fi    
}

_fix_network() {
    echo "Fix network settings in ${1}..."
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
    # fix network in container
    rm "${1}"/etc/resolv.conf
    echo "nameserver 8.8.8.8" > "${1}"/etc/resolv.conf
}

_create_archboot_db() {
    echo "Creating archboot repository db..."
    #shellcheck disable=SC2046
    LANG=C repo-add -q "${1}"/archboot.db.tar.gz $(find "${1}"/ -type f ! -name '*.sig')
}

_pacman_parameters() {
    # building for different architecture using binfmt
    if [[ "${2}" == "use_binfmt" ]]; then
        _PACMAN="${_NSPAWN} ${1} pacman"
        _PACMAN_CACHEDIR=""
        _PACMAN_DB="--dbpath /blankdb"
    # building for running architecture
    else
        _PACMAN="pacman --root ${1}"
        _PACMAN_CACHEDIR="--cachedir ${1}/${_CACHEDIR}"
        _PACMAN_DB="--dbpath ${1}/blankdb"
    fi
    [[ -d "${1}"/blankdb ]] || mkdir "${1}"/blankdb
    # defaults used on every pacman call
    _PACMAN_DEFAULTS="--config ${_PACMAN_CONF} ${_PACMAN_CACHEDIR} --ignore systemd-resolvconf --noconfirm"
}

_pacman_key() {
    echo "Adding ${_GPG_KEY} to container..."
    [[ -d "${1}"/usr/share/archboot/gpg ]] || mkdir -p "${1}"/usr/share/archboot/gpg
    cp "${_GPG_KEY}" "${1}"/"${_GPG_KEY}"
    echo "Adding ${_GPG_KEY_ID} to container trusted keys..."
    ${_NSPAWN} "${1}" pacman-key --add "${_GPG_KEY}" &>/dev/null
    ${_NSPAWN} "${1}" pacman-key --lsign-key "${_GPG_KEY_ID}" &>/dev/null
    echo "Removing ${_GPG_KEY} from container..."
    rm "${1}/${_GPG_KEY}"
}

_pacman_key_system() {
    echo "Adding ${_GPG_KEY_ID} to trusted keys..."
    pacman-key --add "${_GPG_KEY}" &>/dev/null
    pacman-key --lsign-key "${_GPG_KEY_ID}" &>/dev/null
}

_cachedir_check() {
    if grep -q ^CacheDir /etc/pacman.conf; then
        echo "Error: CacheDir is set in /etc/pacman.conf. Aborting..."
        exit 1
    fi
}

# vim: set ft=sh ts=4 sw=4 et:
