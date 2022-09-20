#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
LANG="C"
_BASENAME="$(basename "${0}")"
_RUNNING_ARCH="$(uname -m)"
_PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
_PACMAN_CONF="/etc/pacman.conf"
_FIX_PACKAGES="libunwind libelf libevent python talloc gdbm fuse3 gcc-libs perl glibc libtiff glib2 libcups harfbuzz avahi nss p11-kit libp11-kit fuse tpm2-tss libsecret smbclient libcap tevent libbsd libldap tdb ldb libmd jansson libsasl pcre2"
_XORG_PACKAGE="xorg"
_VNC_PACKAGE="tigervnc"
_WAYLAND_PACKAGE="egl-wayland"
_STANDARD_PACKAGES="gparted nss-mdns"
_STANDARD_BROWSER="chromium"
[[ "${_RUNNING_ARCH}" == "riscv64" ]] && _STANDARD_BROWSER="firefox"
_GRAPHICAL_PACKAGES="${_XORG_PACKAGE} ${_WAYLAND_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_XFCE_PACKAGES} ${_GNOME_PACKAGES} ${_PLASMA_PACKAGES}"

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

_loop_check() {
    if ! [[ -b /dev/loop0 ]]; then
        modprobe loop > /dev/null 2>&1
        losetup -f  > /dev/null 2>&1
        ! [[ -b /dev/loop0 ]] && (echo "ERROR: No /dev/loop0 available. Aborting..."; exit 1)
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
        echo "Generate pacman keyring in container ..."
        systemd-nspawn -q -D "${1}" pacman-key --init >/dev/null 2>&1
        systemd-nspawn -q -D "${1}" pacman-key --populate "${_KEYRING}" >/dev/null 2>&1
    else
        cp -ar /etc/pacman.d/gnupg "${1}"/etc/pacman.d >/dev/null 2>&1
    fi
}

_x86_64_pacman_use_default() {
    # use pacman.conf with disabled [testing] repository
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "Use system's ${_PACMAN_CONF} ..."
    else
        echo "Copy ${_CUSTOM_PACMAN_CONF} to ${_PACMAN_CONF} ..."
        cp "${_PACMAN_CONF}" "${_PACMAN_CONF}".old
        cp "${_CUSTOM_PACMAN_CONF}" "${_PACMAN_CONF}"
    fi
    # use mirrorlist with enabled rackspace mirror
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "Use system's ${_PACMAN_MIRROR} ..."    
    else
        echo "Copy ${_CUSTOM_MIRRORLIST} to ${_PACMAN_MIRROR} ..."
        cp "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}".old
        cp "${_CUSTOM_MIRRORLIST}" "${_PACMAN_MIRROR}"
    fi
}

_x86_64_pacman_restore() {
    # restore pacman.conf and mirrorlist
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "System's ${_PACMAN_CONF} used ..."
    else
        echo "Restore system's ${_PACMAN_CONF} ..."
         cp "${_PACMAN_CONF}".old "${_PACMAN_CONF}"
    fi
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "System's ${_PACMAN_MIRROR} used ..."
    else
        echo "Restore system's ${_PACMAN_MIRROR} ..."
        cp "${_PACMAN_MIRROR}".old "${_PACMAN_MIRROR}"
    fi    
}

_fix_network() {
    echo "Fix network settings in ${1} ..."
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
    # fix network in container
    rm "${1}"/etc/resolv.conf
    echo "nameserver 8.8.8.8" > "${1}"/etc/resolv.conf
}

_create_archboot_db() {
    echo "Creating archboot repository db ..."
    #shellcheck disable=SC2046
    LANG=C repo-add -q "${1}"/archboot.db.tar.gz $(find "${1}"/ -type f ! -name '*.sig')
}
