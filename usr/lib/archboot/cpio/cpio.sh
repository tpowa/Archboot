#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-cpio.sh - modular tool for building an initramfs image
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

_CONFIG=""
_CPIO=/usr/lib/archboot/cpio/hooks
_GENERATE_IMAGE=""
_TARGET_DIR=""
declare -A _INCLUDED_MODS _MOD_PATH

_usage() {
    cat <<EOF
ARCHBOOT CPIO
-------------
Tool for creating an archboot initramfs image.

 -h               Display this message and exit

 -c <config>      Use <config> file
 -k <kernel>      Use specified <kernel>

 -g <path>        Generate cpio image and write to specified <path>
 -d <dir>         Generate image into <dir>

usage: ${0##*/} <options>
EOF
    exit 0
}

_abort() {
    echo "ERROR:" "$@"
    exit 1
}

_cleanup() {
    if [[ -n "${_BUILD_DIR}" ]]; then
        rm -rf -- "${_BUILD_DIR}"
    fi
}

_builtin_modules() {
    while IFS=.= read -rd '' _MODULE _FIELD _VALUE; do
        _INCLUDED_MODS[${_MODULE//-/_}]=2
        case "$_FIELD" in
            alias)  _INCLUDED_MODS["${_VALUE//-/_}"]=2
                    ;;
        esac
    done <"${_MODULE_DIR}/modules.builtin.modinfo"
}

_map() {
    _RETURN=0
    for i in "${@:2}"; do
        # shellcheck disable=SC1105,SC2210,SC2035
        "${1}" "${i}" || (( $# > 255 ? _RETURN=1 : ++_RETURN ))
    done
    return "${_RETURN}"
}

_filter_modules() {
    # Add modules to the rootfs, filtered by grep.
    #   $@: filter arguments to grep
    #   -f FILTER: ERE to filter found modules
    local -i _COUNT=0
    _MOD_INPUT="" OPTIND="" OPTARG="" _MOD_FILTER=()
    while getopts ':f:' _FLAG; do
        [[ "${_FLAG}" = "f" ]] && _MOD_FILTER+=("$OPTARG")
    done
    shift $(( OPTIND - 1 ))
    # shellcheck disable=SC2154
    while read -r -d '' _MOD_INPUT; do
        (( ++_COUNT ))
        for f in "${_MOD_FILTER[@]}"; do
            [[ "${_MOD_INPUT}" =~ $f ]] && continue 2
        done
        _MOD_INPUT="${_MOD_INPUT##*/}" _MOD_INPUT="${_MOD_INPUT%.ko*}"
        printf '%s\n' "${_MOD_INPUT//-/_}"
    done < <(find "${_MODULE_DIR}" -name '*.ko*' -print0 2>"${_NO_LOG}" | grep -EZz "$@")
    (( _COUNT ))
}

_all_modules() {
    # Add modules to the initcpio.
    #   $@: arguments to all_modules
    local -a _MODS
    mapfile -t _MODS < <(_filter_modules "$@")
    _map _module "${_MODS[@]}"
    return $(( !${#_MODS[*]} ))
}

_module() {
    # Add a kernel module to the rootfs. Dependencies will be
    # discovered and added.
    #   $1: module name
    _CHECK="" _MOD="" _SOFT=() _DEPS=() _FIELD="" _VALUE="" _FW=()
    if [[ "${1}" == *\? ]]; then
        set -- "${1%?}"
    fi
    _CHECK="${1%.ko*}" _CHECK="${_CHECK//-/_}"
    # skip expensive stuff if this module has already been added
    (( _INCLUDED_MODS["${_CHECK}"] == 1 )) && return
    while IFS=':= ' read -r -d '' _FIELD _VALUE; do
        case "${_FIELD}" in
            filename)   # Only add modules with filenames that look like paths (e.g.
                        # it might be reported as "(builtin)"). We'll defer actually
                        # checking whether or not the file exists -- any errors can be
                        # handled during module install time.
                        if [[ "${_VALUE}" == /* ]]; then
                            _MOD="${_VALUE##*/}" _MOD="${_MOD%.ko*}"
                            _MOD_PATH[".${_VALUE}"]=1
                            _INCLUDED_MODS["${_MOD//-/_}"]=1
                        fi
                        ;;
            depends)    IFS=',' read -r -a _DEPS <<< "${_VALUE}"
                        _map _module "${_DEPS[@]}"
                        ;;
            softdep)    read -ra _SOFT <<<"${_VALUE}"
                        for i in "${_SOFT[@]}"; do
                            [[ ${i} == *: ]] && continue
                            _module "${i}?"
                        done
                        ;;
        esac
    done < <(modinfo -k "${_KERNELVERSION}" -0 "${_CHECK}" 2>"${_NO_LOG}")
}

_full_dir() {
    tar -C / --hard-dereference -cpf - ."${1}" | tar -C "${_ROOTFS}" -xpf -
}

_dir() {
    [[ -d "${_ROOTFS}${1}" ]] || mkdir -p "${_ROOTFS}${1}"
}

_symlink() {
    _LINK_NAME="${1}" _LINK_SOURCE="${2:-$1}"
    # find out the link target
    if [[ "${_LINK_NAME}" == "${_LINK_SOURCE}" ]]; then
        _LINK_DEST="$(find "${_LINK_SOURCE}" -prune -printf '%l')"
        # use relative path if the target is a file in the same directory as the link
        # anything more would lead to the insanity of parsing each element in its path
        if [[ "${_LINK_DEST}" != *'/'* && ! -L "${_LINK_NAME%/*}/${_LINK_DEST}" ]]; then
            _LINK_SOURCE="${_LINK_DEST}"
        else
            _LINK_SOURCE="$(realpath -eq -- "${_LINK_SOURCE}")"
        fi
    elif [[ -L "${_LINK_SOURCE}" ]]; then
        _LINK_SOURCE="$(realpath -eq -- "${_LINK_SOURCE}")"
    fi
    _dir "${_LINK_NAME%/*}"
    ln -sfn "${_LINK_SOURCE}" "${_ROOTFS}${_LINK_NAME}"
}

_file() {
    if [[ ! -e "${_ROOTFS}${1}" ]]; then
        tar --hard-dereference -C / -cpf - ."${1}" | tar -C "${_ROOTFS}" -xpf - || return 1
        if [[ -L "${1}" ]]; then
            _LINK_SOURCE="$(realpath -- "${1}")"
            _file  "${_LINK_SOURCE}"
        fi
    fi
}

_file_rename() {
    tar --hard-dereference --transform="s|${1}|${2}|" -C / -cpf - ."${1}" | tar -C "${_ROOTFS}" -xpf -
}

_binary() {
    _BIN="$(type -P "${1}")"
    _file "${_BIN}"
}

_init_rootfs() {
    # creates a temporary directory for the rootfs and initialize it with a
    # basic set of necessary directories and symlinks
    _TMPDIR="$(mktemp -d --tmpdir mkinitcpio.XXXX)"
    _ROOTFS="${2:-${_TMPDIR}/root}"
    # basic directory structure
    mkdir -p "${_ROOTFS}"/{dev,etc,mnt,proc,root,run,sys,sysroot,tmp,usr/{local{,/bin,/sbin,/lib},lib,bin},var}
    ln -s "usr/lib" "${_ROOTFS}/lib"
    ln -s "bin" "${_ROOTFS}/usr/sbin"
    ln -s "usr/bin" "${_ROOTFS}/bin"
    ln -s "usr/bin" "${_ROOTFS}/sbin"
    ln -s "/run" "${_ROOTFS}/var/run"
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        ln -s "lib" "${_ROOTFS}/usr/lib64"
        ln -s "usr/lib" "${_ROOTFS}/lib64"
    fi
    # kernel module dir
    [[ "${_KERNELVERSION}" != 'none' ]] && mkdir -p "${_ROOTFS}/usr/lib/modules/${_KERNELVERSION}/kernel"
    # mount tables
    ln -s ../proc/self/mounts "${_ROOTFS}/etc/mtab"
    : >"${_ROOTFS}/etc/fstab"
    # add a blank ld.so.conf to keep ldconfig happy
    : >"${_ROOTFS}/etc/ld.so.conf"
    echo "${_TMPDIR}"
}

_run_hook() {
    if [[ ! -f ${_CPIO}/"${1}" ]]; then
        _abort "Hook ${1} cannot be found!"
    fi
    # source
    unset -f _run
    # shellcheck disable=SC1090
    . "${_CPIO}/${1}"
    _run
}

_install_modules() {
    echo "Adding kernel modules..."
    tar --hard-dereference -C / -cpf - "$@" | tar -C "${_ROOTFS}" -xpf -
    echo "Generating module dependencies..."
    _map _file "${_MODULE_DIR}"/modules.{builtin,builtin.modinfo,order}
    depmod -b "${_ROOTFS}" "${_KERNELVERSION}"
    # remove all non-binary module.* files (except devname for on-demand module loading
    # and builtin.modinfo for checking on builtin modules)
    rm "${_ROOTFS}${_MODULE_DIR}"/modules.!(*.bin|*.modinfo|devname|softdep)
}

_install_libs() {
    # add libraries for binaries in bin/ and /lib/systemd
    echo "Adding libraries for /bin and /lib/systemd..."
    while read -r i; do
        [[ -e "${i}" ]] && _file "${i}"
    done < <(objdump -p "${_ROOTFS}"/bin/* "${_ROOTFS}"/lib/systemd/{systemd-*,libsystemd*} 2>${_NO_LOG} |
                grep 'NEEDED' | sort -u | sed -e 's#NEEDED##g' -e 's# .* #/lib/#g')
    echo "Checking libraries in /lib..."
    _LIB_COUNT=""
    while true; do
        while read -r i; do
            [[ -e "${i}" ]] && _file "${i}"
        done < <(objdump -p "${_ROOTFS}"/lib/*.so* |
                grep 'NEEDED' | sort -u | sed -e 's#NEEDED##g' -e 's# .* #/lib/#g')
        # rerun loop if new libs were discovered, else break
        _LIB_COUNT2="$(ls "${_ROOTFS}"/lib/*.so* | wc -l)"
        [[ "${_LIB_COUNT}" == "${_LIB_COUNT2}" ]] && break
        _LIB_COUNT="${_LIB_COUNT2}"
    done
}

_create_cpio() {
    case "${_COMP}" in
        cat)    echo "Creating uncompressed image: ${_GENERATE_IMAGE}"
                unset _COMP_OPTS
                ;;
        *)      echo "Creating ${_COMP} compressed image: ${_GENERATE_IMAGE}"
                ;;&
        xz)     _COMP_OPTS=('-T0' '--check=crc32' "${_COMP_OPTS[@]}")
                ;;
        lz4)    _COMP_OPTS=('-l' "${_COMP_OPTS[@]}")
                ;;
        zstd)   _COMP_OPTS=('-T0' "${_COMP_OPTS[@]}")
                ;;
    esac
    pushd "${_ROOTFS}" >"${_NO_LOG}" || return
    # Reproducibility: set all timestamps to 0
    find . -mindepth 1 -execdir touch -hcd "@0" "{}" +
    find . -mindepth 1 -printf '%P\0' | sort -z | LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            ${_COMP} "${_COMP_OPTS[@]}" > "${_GENERATE_IMAGE}" || _abort "Image creation failed!"
    popd >"${_NO_LOG}" || return
}
