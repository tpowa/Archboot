#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# archboot-cpio.sh - modular tool for building initramfs images
# focused and optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

shopt -s extglob

. /usr/lib/archboot/common.sh
. /usr/lib/archboot/cpio/cpio.sh

if [[ -z "${1}" ]]; then
    _usage
fi
_root_check

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
            exit 0
            ;;
    esac
    shift
done

#shellcheck disable="SC1090"
! . "${_CONFIG}" 2>"${_NO_LOG}" && _abort "Failed to read ${_CONFIG} configuration file"
if [[ -z "${_KERNEL}" ]]; then
    echo "Trying to autodetect ${_RUNNING_ARCH} kernel..."
    [[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _KERNEL="/usr/lib/modules/*/vmlinuz"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KERNEL="/boot/Image.gz"
fi
# allow * in config
#shellcheck disable=SC2116,2086
_KERNEL="$(echo ${_KERNEL})"
echo "Using kernel: ${_KERNEL}"
if [[ ! -f "${_KERNEL}" ]]; then
    _abort "kernel image does not exist!"
fi
_KERNELVERSION="$(_kver "${_KERNEL}")"
_MODULE_DIR="/lib/modules/${_KERNELVERSION}"
[[ -d "${_MODULE_DIR}" ]] || _abort "${_MODULE_DIR} is not a valid kernel module directory!"
_BUILD_DIR="$(_init_rootfs "${_KERNELVERSION}" "${_TARGET_DIR}")" || exit 1
_ROOTFS="${_TARGET_DIR}:-${_BUILD_DIR}/root}"
if (( ${#_HOOKS[*]} == 0 )); then
    _abort "No hooks found in config file!"
fi
if [[ -n "${_GENERATE_IMAGE}" || -n "${_TARGET_DIR}" ]]; then
    echo "Starting build: ${_KERNELVERSION}"
else
    echo "Starting dry run: ${_KERNELVERSION}"
fi
_builtin_modules
_map _run_hook "${_HOOKS[@]}"
_install_modules "${!_MOD_PATH[@]}"
# this is simply a nice-to-have -- it doesn't matter if it fails.
ldconfig -r "${_ROOTFS}" &>"${_NO_LOG}"
# remove /var/cache/ldconfig/aux-cache for reproducibility
rm -f -- "${_ROOTFS}/var/cache/ldconfig/aux-cache"
# Set umask to create initramfs images as 600
umask 077
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    _create_cpio "${_GENERATE_IMAGE}" "${_COMP}" || exit 1
elif [[ -n "${_TARGET_DIR}" ]]; then
    msg "Build complete."
else
    msg "Dry run complete, use -g IMAGE to generate a real image"
fi

# vim: set ft=sh ts=4 sw=4 et:
