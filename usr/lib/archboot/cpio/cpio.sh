#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-cpio.sh - modular tool for building an initramfs image
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

_CONFIG=""
_CPIO=/usr/lib/archboot/cpio/hooks
_GENERATE_IMAGE=""
_TARGET_DIR=""

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

_parameters() {
while [ $# -gt 0 ]; do
    case "${1}" in
        -c) shift
            _CONFIG="${1}"
            ;;
        -k) shift
            _KERNEL="${1}"
            ;;
        -d) shift
            _TARGET_DIR="${1}"
            ;;
        -g) shift
            [[ -d "${1}" ]] && _abort "Invalid image path -- ${1} is a directory!"
            if ! _GENERATE_IMAGE="$(readlink -f "${1}")" || [[ ! -e "${_GENERATE_IMAGE%/*}" ]]; then
                _abort "Unable to write to path!" "${1}"
            fi
            ;;
        -h) _usage
            ;;
    esac
    shift
done
}

_cleanup() {
    if [[ -n "${_BUILD_DIR}" ]]; then
        rm -rf -- "${_BUILD_DIR}"
    fi
}

_map() {
    _RETURN=0
    for i in "${@:2}"; do
        # shellcheck disable=SC1105,SC2210,SC2035
        "${1}" "${i}" || (( $# > 255 ? _RETURN=1 : ++_RETURN ))
    done
    return "${_RETURN}"
}

_loaded_mods() {
modinfo -k ${_KERNELVERSION} --field filename $(cut -d ' ' -f1 </proc/modules) \
$(modinfo --field depends $(cut -d ' ' -f1 </proc/modules) | sed -e 's#,# #g') \
$(modinfo --field softdep $(cut -d ' ' -f1 </proc/modules) | sed -e 's#.*:\ # #g') 2>/dev/null |\
grep -v builtin
modinfo -k ${_KERNELVERSION} --field firmware $(cut -d ' ' -f1 </proc/modules) | sed -e 's#^#/usr/lib/firmware/#g' -e 's#$#.zst#g'
}

_filter_mods() {
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
        printf '%s\n' "${_MOD_INPUT}"
    done < <(find "${_MODULE_DIR}" -name '*.ko*' -print0 2>"${_NO_LOG}" | grep -EZz "$@")
    (( _COUNT ))
}

_all_mods() {
    # Add modules to the initcpio.
    #   $@: arguments to all_mods
    mapfile -t _CHECKED_MODS < <(_filter_mods "$@")
    _map _mod "${_CHECKED_MODS[@]}"
}

_mod() {
    _MODS+="${1} "
}

_full_dir() {
    tar -C / --hard-dereference -cpf - "${1##/}" | tar -C "${_ROOTFS}" -xpf -
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
    _FILES+="${1##/} "
    if [[ -L "${1}" ]]; then
        _LINK_SOURCE="$(realpath -- "${1}")"
        _file  "${_LINK_SOURCE}"
    fi
}

_install_files() {
    # shellcheck disable=SC2086
    tar --hard-dereference -C / -cpf - ${_FILES} | tar -C "${_ROOTFS}" -xpf - || return 1
    _FILES=""
}

_file_rename() {
    _SRC="${1##/}" _DEST="${2##/}"
    tar --hard-dereference --transform="s|${_SRC}|${_DEST}|" -C / -cpf - "${_SRC}" | tar -C "${_ROOTFS}" -xpf -
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

_install_mods() {
    # Checking kernel module dependencies:
    # first try, pull in the easy modules
    _MOD_DEPS="$(modinfo -k "${_KERNELVERSION}" -F depends $_MODS 2>/dev/null | sed -e 's#,# #g' | tr " " "\n" | sort -u) \
               $(modinfo -k "${_KERNELVERSION}" -F softdep $_MODS 2>/dev/null | sed -e 's#.*: # #g' | tr " " "\n" | sort -u)"
    _DEP_COUNT=0
    # next tries, ensure to catch all modules with depends
    while true; do
        _MOD_DEPS="$(echo $_MOD_DEPS \
                $(modinfo -k "${_KERNELVERSION}" -F depends $_MOD_DEPS 2>/dev/null | sed -e 's#,# #g' | tr " " "\n" | sort -u) \
                $(modinfo -k "${_KERNELVERSION}" -F softdep $_MOD_DEPS 2>/dev/null | sed -e 's#.*: # #g' | tr " " "\n" | sort -u) \
                | tr " " "\n" | sort -u)"
        _DEP_COUNT2="$(echo "$_MOD_DEPS" | wc -w)"
        [[ "${_DEP_COUNT}" == "${_DEP_COUNT2}" ]] && break
        _DEP_COUNT="${_DEP_COUNT2}"
    done
    _map _file "${_MODULE_DIR}"/modules.{builtin,builtin.modinfo,order}
    _install_files
    # Adding kernel modules:
    # - pull in all modules with depends
    # - builtin needs to be removed
    # - all starting / needs to be removed from paths
    tar --hard-dereference -C / -cpf - $(modinfo  -k "${_KERNELVERSION}" -F filename $_MODS $_MOD_DEPS 2>/dev/null \
    | grep -v builtin | sed -e 's#^/##g' -e 's# /# #g') | tar -C "${_ROOTFS}" -xpf -
    # generate new kernel module dependencies"
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
    done < <(objdump -p "${_ROOTFS}"/bin/* "${_ROOTFS}"/lib/systemd/{systemd-*,libsystemd*} 2>"${_NO_LOG}" |
                grep 'NEEDED' | sort -u | sed -e 's#NEEDED##g' -e 's# .* #/lib/#g')
    _install_files
    echo "Checking libraries in /lib..."
    _LIB_COUNT=""
    while true; do
        while read -r i; do
            [[ -e "${i}" ]] && _file "${i}"
        done < <(objdump -p "${_ROOTFS}"/lib/*.so* |
                grep 'NEEDED' | sort -u | sed -e 's#NEEDED##g' -e 's# .* #/lib/#g')
        _install_files
        # rerun loop if new libs were discovered, else break
        _LIB_COUNT2="$(echo "${_ROOTFS}"/lib/*.so* | wc -w)"
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
