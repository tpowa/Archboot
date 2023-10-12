#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# archboot-cpio.sh - modular tool for building initramfs images
# simplified, stripped down, optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

shopt -s extglob

. /usr/lib/archboot/common.sh
. /usr/lib/archboot/cpio/cpio.sh
# needed files/directories
_CONFIG=""
_CPIO=/usr/lib/archboot/cpio/
# options and runtime data
_GENERATE_IMAGE=""
_TARGET_DIR=""
declare -A _addedmodules _modpaths
# Sanitize environment further
# GREP_OPTIONS="--color=always" will break everything
# CDPATH can affect cd and pushd
# LIBMOUNT_* options can affect findmnt and other tools
unset GREP_OPTIONS CDPATH "${!LIBMOUNT_@}"

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
}

_build_cpio() {
    case "${_COMP}" in
        cat)    echo "Creating uncompressed initcpio image: ${_OUT}"
                unset _COMP_OPTS
                ;;
        *)      echo "Creating ${_COMP} compressed initcpio image: ${_OUT}"
                ;;
        xz)     _COMP_OPTS=('-T0' '--check=crc32' "${_COMP_OPTS[@]}")
                ;;
        lz4)    _COMP_OPTS=('-l' "${_COMP_OPTS[@]}")
                ;;
        zstd)   _COMP_OPTS=('-T0' "${_COMP_OPTS[@]}")
                ;;
    esac
    # Reproducibility: set all timestamps to 0
    find . -mindepth 1 -execdir touch -hcd "@0" "{}" +
    # If this pipeline changes, |pipeprogs| below needs to be updated as well.
    find . -mindepth 1 -printf '%P\0' |
            sort -z |
            LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            ${_COMP} "${_COMP_OPTS[@]}" > "${_OUT}" || _abort "initcpio image creation failed!"
}

preload_builtin_modules() {
    local modname field value
    # Prime the _addedmodules list with the builtins for this kernel.
    # kmod>=27 and kernel >=5.2 required!
    while IFS=.= read -rd '' modname field value; do
        _addedmodules[${modname//-/_}]=2
        case "$field" in
            alias)
                _addedmodules["${value//-/_}"]=2
                ;;
        esac
    done <"$_d_kmoduledir/modules.builtin.modinfo"
}

if [[ -z "$1" ]]; then
    _usage
    exit 0
fi
_root_check

while :; do
    case "${1}" in
        -c) shift
            ${_CONFIG}="${1}"
            ;;
        -k) shift
            KERNEL="${1}"
            ;;
        -d) shift
            ${_TARGET_DIR}="${1}"
            ;;
        -g) shift
            [[ -d "${1}" ]] && _abort "Invalid image path -- ${1} is a directory!"
            if ! ${_GENERATE_IMAGE}="$(readlink -f "$1")" || [[ ! -e "${_GENERATE_IMAGE%/*}" ]]; then
                _abort "Unable to write to path!" "${1}"
            fi
            ;;
        -h) _usage
            exit 0
            ;;
        *) _usage ;;
    esac
    shift
done

#shellcheck disable="SC1090"
! . "${_CONFIG}" 2>"${_NO_LOG}" && _abort "Failed to read configuration '%s'" "${_CONFIG}"
if [[ -z "${KERNEL}" ]]; then
    msg "Trying to autodetect ${_RUNNING_ARCH} kernel..."
    [[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && KERNEL="/usr/lib/modules/*/vmlinuz"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && KERNEL="/boot/Image.gz"
fi
# allow * in config
#shellcheck disable=SC2116,2086
KERNEL="$(echo ${KERNEL})"
msg "Using kernel: ${KERNEL}"
if [[ ! -f "${KERNEL}" ]]; then
    _abort "kernel image does not exist!"
fi
_KERNELVERSION="$(_kver "${KERNEL}")"
_d_kmoduledir="/lib/modules/${_KERNELVERSION}"
[[ -d "$_d_kmoduledir" ]] || _abort "'$_d_kmoduledir' is not a valid kernel module directory"
_d_workdir="$(initialize_buildroot "${_KERNELVERSION}" "${_TARGET_DIR}")" || exit 1
_ROOTFS="${_TARGET_DIR}:-$_d_workdir/root}"
_hooks=("${HOOKS[@]}")
if (( ${#_hooks[*]} == 0 )); then
    _abort "Invalid config: No hooks found"
fi
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    # check for permissions. if the image doesn't already exist,
    # then check the directory
    if [[ ( -e ${_GENERATE_IMAGE} && ! -w ${_GENERATE_IMAGE} ) ||
            ( ! -d ${_GENERATE_IMAGE%/*} || ! -w ${_GENERATE_IMAGE%/*} ) ]]; then
        _abort "Unable to write to '%s'" "${_GENERATE_IMAGE}"
    fi
    msg "Starting build: '%s'" "${_KERNELVERSION}"
elif [[ -n "${_TARGET_DIR}" ]]; then
    msg "Starting build: '%s'" "${_KERNELVERSION}"
else
    msg "Starting dry run: '%s'" "${_KERNELVERSION}"
fi
# set functrace and trap to catch errors in add_* functions
declare -i _builderrors=0
preload_builtin_modules
map run_build_hook "${_hooks[@]}" || (( ++_builderrors ))
install_modules "${!_modpaths[@]}"
# this is simply a nice-to-have -- it doesn't matter if it fails.
ldconfig -r "${_ROOTFS}" &>"${_NO_LOG}"
# remove /var/cache/ldconfig/aux-cache for reproducibility
rm -f -- "${_ROOTFS}/var/cache/ldconfig/aux-cache"
# Set umask to create initramfs images as 600
umask 077
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    _build_cpio "${_GENERATE_IMAGE}" "${COMPRESSION}" || exit 1
elif [[ -n "${_TARGET_DIR}" ]]; then
    msg "Build complete."
else
    msg "Dry run complete, use -g IMAGE to generate a real image"
fi
exit $(( !!_builderrors ))

# vim: set ft=sh ts=4 sw=4 et:
