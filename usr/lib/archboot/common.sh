#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_AMD_UCODE="boot/amd-ucode.img"
_CACHEDIR="/var/cache/pacman/pkg"
_CONFIG_DIR="/etc/archboot"
_DLPROG="curl -L -s"
_FIX_PACKAGES=(
  gcc-libs
  glib2
  glibc
  icu
  libelf
  libevent
  nss
  pcre2
  talloc
  terminus-font
)
_INTEL_UCODE="boot/intel-ucode.img"
_KERNELPKG="linux"
_KEYRING=(archlinux-keyring)
_LABEL="Exit"
_LOCAL_DB="${_CACHEDIR}/archboot.db"
_LOG="/dev/tty11"
_MAN_INFO_PACKAGES=(
  man-db
  man-pages
  texinfo
)
_MEM_TOTAL="$(rg -o 'MemTotal.* (\d+)' -r '$1' /proc/meminfo)"
_NO_LOG="/dev/null"
_OSREL="/usr/share/archboot/base/etc/os-release"
_PACMAN_CONF="/etc/pacman.conf"
_PACMAN_LIB="/var/lib/pacman"
_PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
_PUB="public_html"
_RSYNC="rsync -a -q --delete --delete-delay"
_RUNNING_ARCH="$(uname -m)"
_RUNNING_KERNEL="$(uname -r)"
_SPLASH="/usr/share/archboot/uki/archboot-background.bmp"
_STANDARD_PACKAGES=(
  gparted
  mtools
  noto-fonts
  xorg-xhost
)
_TEMPLATE="/tmp/archboot-autorun.template"
if [[ ! -e "${_TEMPLATE}" ]]; then
    { echo "#!/bin/bash"
    echo ". /usr/lib/archboot/common.sh"
    echo ". /usr/lib/archboot/installer/common.sh"
    echo "echo \"Automatic Archboot - Arch Linux Installation:\""
    echo "echo \"Logging is done on ${_LOG}...\""
    } >> "${_TEMPLATE}"
fi
_VNC_PACKAGE="tigervnc"
_WAYLAND_PACKAGE="egl-wayland"
_XORG_PACKAGE="xorg"

_BASENAME=${0##*/}
_ANSWER="/.${_BASENAME}"
_VC_NUM="${_LOG/\/dev\/tty/}"
_VC="VC${_VC_NUM}"
if echo "${_BASENAME}" | rg -qw aarch64; then
    _ARCHBOOT="archboot-arm"
    _KEYRING+=(archlinuxarm-keyring)
    _ARCH="aarch64"
elif echo "${_BASENAME}" | rg -qw riscv64; then
    _ARCHBOOT="archboot-riscv"
    _ARCH="riscv64"
else
    _ARCHBOOT="archboot"
    _ARCH="x86_64"
fi
_CONFIG_LATEST="${_ARCH}-latest.conf"
_CONFIG_LOCAL="${_ARCH}-local.conf"
# chromium is now working on riscv64
[[ "${_RUNNING_ARCH}" == "riscv64" ]] && _STANDARD_BROWSER="firefox"
if [[ -d "${_ISO_HOME}" ]]; then
    _NSPAWN="systemd-nspawn -q --bind ${_ISO_HOME} -D"
else
    _NSPAWN="systemd-nspawn -q -D"
fi

if [[ "${_ARCH}" == "x86_64" ]]; then
    _CMDLINE="console=ttyS0,115200 console=tty0 audit=0 systemd.show_status=auto"
elif [[ "${_ARCH}" == "aarch64" ]]; then
    _INTEL_UCODE=""
    _CMDLINE="nr_cpus=1 console=ttyAMA0,115200 console=tty0 loglevel=4 audit=0 systemd.show_status=auto"
fi

### check for root
_root_check() {
    if ! [[ ${UID} -eq 0 ]]; then
        echo "ERROR: Please run as root user!"
        exit 1
    fi
}

### check for Archboot environment
_archboot_check() {
if ! rg -qw 'archboot' /etc/hostname; then
    echo "This script should only be run in booted Archboot Environment. Aborting..."
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

# returns: whatever dialog did
_dialog() {
    dialog --cancel-label "Back" --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

# $1: percentage $2: message
_progress() {
cat 2>"${_NO_LOG}" <<EOF
XXX
${1}
${2}
XXX
EOF
}

# $1: start percentage $2: end percentage $3: message $4: sleep time
_progress_wait() {
    _COUNT=${1}
    while [[ -e "${_W_DIR}/.archboot" || -e /.archboot ]]; do
        if [[ "${_COUNT}" -lt "${2}" ]]; then
            _progress "${_COUNT}" "${3}"
        fi
        if [[ "${_COUNT}" -gt "${2}" ]]; then
            _progress "${2}" "${3}"
        fi
        _COUNT="$((_COUNT+1))"
        read -r -t "${4}"
    done
}

_show_login() {
    [[ -e "/.${_ANSWER}-running" ]] && rm "/.${_ANSWER}-running"
    clear
    echo ""
    agetty --show-issue
    echo ""
    cat /etc/motd
}

_abort() {
    if _dialog --yesno "Abort$(echo "${_TITLE}" | choose -f '\|' 4) ?" 5 45; then
        [[ -e "${_ANSWER}-running" ]] && rm "${_ANSWER}-running"
        [[ -e "${_ANSWER}" ]] && rm "${_ANSWER}"
        clear
        exit 1
    else
        _CONTINUE=""
    fi
}

_check() {
    if [[ -e "${_ANSWER}-running" ]]; then
        clear
        echo "${0} already runs on a different console!"
        echo "Please remove ${_ANSWER}-running first to launch ${0}!"
        exit 1
        fi
    : >"${_ANSWER}"
    : >"${_ANSWER}-running"
}

_cleanup() {
    [[ -e "${_ANSWER}-running" ]] && rm "${_ANSWER}-running"
    clear
    exit 0
}

_run_update_environment() {
    if update | rg -q latest-install; then
        update -latest-install
    else
        update -latest
    fi
}

_kver() {
    # x86_64: rg -Noazm 1 'ABCDEF\x00+(.*) \(.*@' -r '$1' ${1}
    # aarch64 compressed and uncompressed:
    # rg -Noazm 1 'Linux version (.*) \(.*@' -r '$1' ${1}
    # riscv64, rg cannot handle compression without extension:
    # zcat ${1} | rg -Noazm 1 'Linux version (.*) \(.*@' -r '$1'
    if [[ -f "${1}" ]]; then
        rg -Noazm 1 'ABCDEF\x00+(.*) \(.*@' -r '$1' "${1}" ||\
        rg -Noazm 1 'Linux version (.*) \(.*@' -r '$1' "${1}" ||\
        zstdcat "${1}" 2>"${_NO_LOG}" | rg -Noazm 1 'Linux version (.*) \(.*@' -r '$1'
    fi
}

### check architecture
_architecture_check() {
    echo "${_BASENAME}" | rg -qw aarch64 && _aarch64_check
    echo "${_BASENAME}" | rg -qw riscv64 && _riscv64_check
    echo "${_BASENAME}" | rg -qw x86_64 && _x86_64_check
}

### check if running in container
_container_check() {
    if rg -q bash /proc/1/sched ; then
        echo "ERROR: Running inside container. Aborting..."
        exit 1
    fi
}

_generate_keyring() {
    # use fresh one on normal systems
    # copy existing gpg cache on Archboot usage
    if ! rg -qw archboot /etc/hostname; then
        # generate pacman keyring
        echo "Generating pacman keyring in container..."
        ${_NSPAWN} "${1}" pacman-key --init &>"${_NO_LOG}"
        ${_NSPAWN} "${1}" pacman-key --populate &>"${_NO_LOG}"
    else
        cp -ar /etc/pacman.d/gnupg "${1}"/etc/pacman.d &>"${_NO_LOG}"
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
    sd '^#ParallelDownloads' 'ParallelDownloads' "${1}"/etc/pacman.conf
    # fix network in container
    rm "${1}"/etc/resolv.conf
    echo "nameserver 8.8.8.8" > "${1}"/etc/resolv.conf
}

_create_archboot_db() {
    echo "Creating reproducible repository db..."
    pushd "${1}" >"${_NO_LOG}" || return 1
    #shellcheck disable=SC2046
    LC_ALL=C.UTF-8 fd -u -t f -E '*.sig' . -X repo-add -q archboot.db.tar
    for i in archboot.{db.tar,files.tar}; do
        mkdir repro
        bsdtar -C repro -xf "${i}" || return 1
        fd --base-directory repro . -u --min-depth 1 -X touch -hcd "@0"
        fd --base-directory repro --strip-cwd-prefix -t f -t l -u --min-depth 1 -0 | sort -z |
            LC_ALL=C.UTF-8 bsdtar -C repro --null -cnf - -T - |
            LC_ALL=C.UTF-8 bsdtar -C repro --null -cf - --format=gnutar @- |
            zstd -T0 -19 >> "${i}.zst" || return 1
        rm -r repro
    done
    rm archboot.{db,files}
    rm archboot.{db,files}.tar
    ln -s archboot.db.tar.zst archboot.db
    ln -s archboot.files.tar.zst archboot.files
    popd >"${_NO_LOG}" || return 1
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
        # needs to be full path
        #shellcheck disable=SC2086
        _PACMAN_CACHEDIR="--cachedir $(realpath "${1}"${_CACHEDIR})"
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
    ${_NSPAWN} "${1}" pacman-key --add "${_GPG_KEY}" &>"${_NO_LOG}"
    ${_NSPAWN} "${1}" pacman-key --lsign-key "${_GPG_KEY_ID}" &>"${_NO_LOG}"
    echo "Removing ${_GPG_KEY} from container..."
    rm "${1}/${_GPG_KEY}"
}

_pacman_key_system() {
    echo "Adding ${_GPG_KEY_ID} to trusted keys..."
    pacman-key --add "${_GPG_KEY}" &>"${_NO_LOG}"
    pacman-key --lsign-key "${_GPG_KEY_ID}" &>"${_NO_LOG}"
}

_cachedir_check() {
    if rg -q '^CacheDir' /etc/pacman.conf; then
        echo "Error: CacheDir is set in /etc/pacman.conf. Aborting..."
        exit 1
    fi
}

_pacman_keyring() {
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
    if [[ -e /etc/systemd/system/pacman-init.service ]]; then
        systemctl stop pacman-init.service
    fi
}

_create_cpio() {
    # $1: path of files
    # $2: output
    # $3: compression
    _COMP_LEVEL="${3:--19}"
    # Reproducibility:
    # set all timestamps to 0
    # fd . -u --min-depth 1 -X touch -hcd "@0"
    # Pipe needed as is, bsdcpio is faster but not reproducible!
    # cpio, pax, tar are slower than bsdtar!
    # LC_ALL=C.UTF-8 bsdtar --null -cnf - -T - |
    # LC_ALL=C.UTF-8 bsdtar --null -cf - --format=newc @-
    # Compression:
    # use zstd it has best compression and decompression
    # Result:
    # Multi CPIO archive, extractable with 3cpio
    pushd "${1}" >"${_NO_LOG}" || return 1
    echo "Creating initramfs:"
    fd . -u --min-depth 1 -X touch -hcd "@0"
    echo "Appending directories..."
    fd . -u -t d -0 | sort -z |
        LC_ALL=C.UTF-8 bsdtar --null -cnf - -T - |
        LC_ALL=C.UTF-8 bsdtar --null -cf - --format=newc @- > "${2}" || _abort "Image creation failed!"
    echo "Appending compressed files..."
    fd . -t f -t l -u -e 'bz2' -e 'gz' -e 'xz' -e 'zst' --min-depth 1 -0 | sort -z |
        LC_ALL=C.UTF-8 bsdtar --null -cnf - -T - |
        LC_ALL=C.UTF-8 bsdtar --null -cf - --format=newc @- >> "${2}" || _abort "Image creation failed!"
    # remove compressed files, timestamps need reset!
    fd . -u -e 'bz2' -e 'gz' -e 'xz' -e 'zst' --min-depth 1 -X rm
    fd . -u --min-depth 1 -X touch -hcd "@0"
    echo "Appending zstd compressed image..."
    fd . -t f -t l -u --min-depth 1 -0 | sort -z |
        LC_ALL=C.UTF-8 bsdtar --null -cnf - -T - |
        LC_ALL=C.UTF-8 bsdtar --null -cf - --format=newc @- |
        zstd -T0 "${_COMP_LEVEL}" >> "${2}" || _abort "Image creation failed!"
    popd >"${_NO_LOG}" || return 1
    echo "Build complete."
}

_reproducibility() {
    # Reproducibility: set all timestamps to 0
    fd . "${1}" -u --min-depth 1 -X touch -hcd "@0"
}
