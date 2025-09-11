#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-cpio.sh - modular tool for building an initramfs image
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_CONFIG=""
_CPIO=/usr/lib/archboot/cpio/hooks
_GENERATE_IMAGE=""
_TARGET_DIR=""

_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Cpio\e[m"
    echo -e "\e[1m---------------\e[m"
    echo "Tool for creating an Archboot initramfs image."
    echo
    echo "Options:"
    echo " -h               Display this message and exit"
    echo " -c <config>      Use <config> file"
    echo " -firmware        split firmware into separate images"
    echo " -g <path>        Generate cpio image and write to specified <path>"
    echo " -d <dir>         Generate image into <dir>"
    echo
    echo -e "Usage: \e[1m${_BASENAME} <options>\e[m"
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
        -firmware)
            _FW_CPIO=1
            ;;
        -d) shift
            _TARGET_DIR="${1}"
            ;;
        -g) shift
            [[ -d "${1}" ]] && _abort "Invalid image path -- ${1} is an existing directory!"
            if ! _GENERATE_IMAGE="$(readlink -f "${1}")" || [[ ! -e "${_GENERATE_IMAGE%/*}" ]]; then
                _abort "Unable to write to path!" "${1}"
            fi
            ;;
        -h|--h|-help|--help|?) _usage
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
    for i in "${@:2}"; do
        "${1}" "${i}"
    done
}

_loaded_mods() {
    #shellcheck disable=SC2046
    modinfo -k "${_KERNELVERSION}" --field filename $(cut -d ' ' -f1 </proc/modules) \
    $(modinfo --field depends $(cut -d ' ' -f1 </proc/modules) | sed -e 's#,# #g') \
    grep -v builtin
    #shellcheck disable=SC2046
    modinfo -k "${_KERNELVERSION}" --field firmware $(cut -d ' ' -f1 </proc/modules) | sed -e 's#^#/usr/lib/firmware/#g' -e 's#$#.zst#g'
    ### get filenames for extraction
    # modules from /sys
    #shellcheck disable=SC2046
    _MODS="$(modinfo --field filename $(find /sys -name modalias) 2>/dev/null | grep -v builtin | sort -u)"
    # Checking kernel module dependencies:
    # first try, pull in the easy modules
    #shellcheck disable=SC2086
    _MOD_DEPS="$(modinfo -F depends ${_MODS} 2>"${_NO_LOG}" | tr "," "\n" | sort -u) \
               $(modinfo -F softdep ${_MODS} 2>"${_NO_LOG}" | tr ".*: " "\n" | sort -u)"
    _DEP_COUNT=0
    # next tries, ensure to catch all modules with depends
    while ! [[ "${_DEP_COUNT}" == "${_DEP_COUNT2}" ]]; do
        _DEP_COUNT="${_DEP_COUNT2}"
        #shellcheck disable=SC2046,SC2086
        _MOD_DEPS="$(echo ${_MOD_DEPS} \
                $(modinfo -F depends ${_MOD_DEPS} 2>"${_NO_LOG}" | tr "," "\n" | sort -u) \
                $(modinfo -F softdep ${_MOD_DEPS} 2>"${_NO_LOG}" | tr ".*: " "\n" | sort -u) \
                | tr " " "\n" | sort -u)"
        _DEP_COUNT2="$(wc -w <<< "${_MOD_DEPS}")"
    done
    #shellcheck disable=SC2086
    _MOD_DEPS="$(modinfo --field filename ${_MOD_DEPS} 2>/dev/null | grep -v builtin | sort -u)"
    # firmware
}

_filter_mods() {
    # only list the module name without extension and directory
    if [[ -z "${2}" ]]; then
        rg "${1}" <<< "${_ALL_MODS}" | rg -o '([a-zA-Z0-9\-_]+).ko$' -r '$1'
    else
        rg "${3}" <<< "${_ALL_MODS}" | rg -v "${2}" | rg -o '([a-zA-Z0-9\-_]+).ko$' -r '$1'
    fi
}

_all_mods() {
    _mod "$(_filter_mods "$@")"
}

_mod() {
    _MODS+=("${1}")
}

_full_dir() {
    tar -C / --hard-dereference -cpf - "${1##/}" | tar -C "${_ROOTFS}" -xpf -
}

_dir() {
    [[ -d "${_ROOTFS}${1}" ]] || mkdir -p "${_ROOTFS}${1}"
}

_symlink() {
    _dir "${1%/*}"
    ln -sfn "${2}" "${_ROOTFS}${1}"
}

_file() {
    if [[ -e "${1}" ]]; then
        _FILES+=("${1##/}")
    else
        echo "Error: ${1} not found!"
    fi
    if [[ -L "${1}" ]]; then
        _file  "$(realpath -- "${1}")"
    fi
}

_install_files() {
    tar --hard-dereference -C / -cpf - "${_FILES[@]}" | tar -C "${_ROOTFS}" -xpf -
    _FILES=()
}

_file_rename() {
    _SRC="${1##/}" _DEST="${2##/}"
    tar --hard-dereference --transform="s|${_SRC}|${_DEST}|" -C / -cpf - "${_SRC}" | tar -C "${_ROOTFS}" -xpf -
}

_binary() {
    _BINARY_PATH="$(type -P "${1}")"
    if [[ -n "${_BINARY_PATH}" ]]; then
        _file "${_BINARY_PATH}"
    else
        echo "Error:${1} not found in path!"
    fi
}

_init_rootfs() {
    # creates a temporary directory for the rootfs and initialize it with a
    # basic set of necessary directories and symlinks
    _TMPDIR="$(mktemp -d --tmpdir archboot-cpio.XXXX)"
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
    # Cascade kernel modules and dependencies:
    # - softdeps are not honored, add them in _mod arrays!
    # - remove duplicate modules
    # - remove builtin modules
    _MOD_FILES=()
    IFS=" " read -r -a _MODS <<< "$(sd ' ' '\n' <<< "${_MODS[@]}" | sort -u | sd '\n' ' ')"
    while true; do
        if [[ -n "${_MOD_FILES[*]}" ]]; then
            _MODS=("$(modinfo -k "${_KERNELVERSION}" -F depends "${_MODS[@]}" | sd '\n' ' ')")
            IFS=" " read -r -a _MODS <<< "$(sd ',' ' ' <<< "${_MODS[@]}" | sd ' ' '\n' | sort -u | sd '\n' ' ')"
        fi
        [[ ${#_MODS[@]} == 0 ]] && break
        mapfile -t _MOD_FILES < <(modinfo  -k "${_KERNELVERSION}" -F filename "${_MODS[@]}" | rg -v builtin)
        _map _file "${_MOD_FILES[@]}"
        _install_files
    done
    # needed files from kernel build for depmod call
    _map _file "${_MOD_DIR}"/modules.{builtin,builtin.modinfo,order}
    _install_files
    # generate new kernel module dependencies"
    depmod -b "${_ROOTFS}" "${_KERNELVERSION}"
    # remove all non-binary module.* files (except devname for on-demand module loading
    # and builtin.modinfo for checking on builtin modules)
    rm "${_ROOTFS}${_MOD_DIR}"/modules.{alias,builtin,dep,order,symbols}
}

_install_libs() {
    # Cascade libraries::
    # - /lib subdirs are mostly ignored!
    # rg -o 'NEEDED.*\[(.*)\]' -r '/lib/$1' # catch libs and add path
    # sort -u # only one time filter
    # sd '/lib//usr' '' # neovim lua lib
    # sd 'libsystemd-' 'systemd/libsystemd-' # libsystemd- libraries don't have systemd/ prefix
    echo "Adding libraries..."
    _LIB_FILES=("${_ROOTFS}"/usr/{bin,lib/{,systemd,security}}/*)
    while true; do
        mapfile -t _LIB_FILES < <(readelf -d "${_LIB_FILES[@]}" 2>"${_NO_LOG}" |\
                                  rg -o 'NEEDED.*\[(.*)\]' -r '/lib/$1' | sort -u | sd '/lib//usr' '' |\
                                  sd 'libsystemd-' 'systemd/libsystemd-')
        [[ ${#_LIB_FILES[@]} == 0 ]] && break
        _map _file "${_LIB_FILES[@]}"
        _install_files
    done
}

_iwl_rt_fw() {
    if ls "${_FW_SRC}/${1}"* &>"${_NO_LOG}"; then
        if [[ -n ${_GENERATE_IMAGE} ]]; then
            echo "Preparing ${2}.img firmware..."
            mv "${_FW_SRC}/${1}"* "${_FW_TMP_SRC}/"
            _create_cpio "${_FW_TMP}" "${_FW_DEST}/${2}.img" &>"${_NO_LOG}" || exit 1
        elif [[ -n "${_TARGET_DIR}" ]]; then
            echo "Saving firmware files to ${_FW_TMP}/${2}..."
            [[ -d "${_FW_TMP}/${2}/${_FW}" ]] || mkdir -p "${_FW_TMP}/${2}/${_FW}"
            mv "${_FW_SRC}/${1}"* "${_FW_TMP}/${2}/${_FW}/"
        fi
    fi
}

_move_fw() {
    # those from firmware basedir belong to corresponding chipsets
    rg -q mediatek <<< "${i}" && mv "${_FW_SRC}"/{mt76*,vpu_*} "${1}"
    rg -q ath9k_htc <<< "${i}" && mv "${_FW_SRC}"/htc_* "${1}"
    rg -q ath11k <<< "${i}" && mv "${_FW_SRC}"/wil6210* "${1}"
    mv "${_FW_SRC}/${i}" "${1}"
}

_cpio_fw() {
    # divide firmware in cpio images
    if [[ -n "${_FW_CPIO}" ]]; then
        _FW=lib/firmware
        _FW_SRC="${_ROOTFS}/${_FW}"
        if [[ -d "${_FW_SRC}" ]]; then
            if [[ -n "${_GENERATE_IMAGE}" ]]; then
                _FW_TMP="${_BUILD_DIR}/fw"
                _FW_TMP_SRC="${_FW_TMP}/${_FW}"
                _FW_DEST="$(dirname "${_GENERATE_IMAGE}")/firmware"
                [[ -d "${_FW_DEST}" ]] || mkdir -p "${_FW_DEST}"
                [[ -d "${_FW_TMP_SRC}" ]] || mkdir -p "${_FW_TMP_SRC}"
            elif [[ -n "${_TARGET_DIR}" ]]; then
                _FW_TMP="/tmp/archboot-firmware"
                [[ -d "${_FW_TMP}" ]] && rm -r "${_FW_TMP}"
            fi
            for i in $(fd --type d --base-directory "${_FW_SRC}" --path-separator '' -d 1); do
                if [[ -n "${_GENERATE_IMAGE}" ]]; then
                    _move_fw "${_FW_TMP_SRC}/"
                    echo "Preparing ${i}.img firmware..."
                    _create_cpio "${_FW_TMP}" "${_FW_DEST}/${i}.img" &>"${_NO_LOG}" || exit 1
                    # remove directory
                    rm -r "${_FW_TMP_SRC:?}"/*
                elif [[ -n "${_TARGET_DIR}" ]]; then
                    echo "Saving firmware files to ${_FW_TMP}/${i}..."
                    [[ -d "${_FW_TMP}/${i}/${_FW}" ]] || mkdir -p "${_FW_TMP}/${i}/${_FW}"
                    _move_fw "${_FW_TMP}/${i}/${_FW}/"
                fi
            done
            # intel wireless
            _iwl_rt_fw "iwl" "iwlwifi" || exit 1
            # ralink wireless
            _iwl_rt_fw "rt" "ralink" || exit 1
        fi
    fi
}
