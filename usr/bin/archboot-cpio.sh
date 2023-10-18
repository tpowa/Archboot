#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# archboot-cpio.sh - modular tool for building initramfs images
# optimized for size and speed
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
            ;;
    esac
    shift
done
#shellcheck disable="SC1090"
. "${_CONFIG}" 2>"${_NO_LOG}" || _abort "Failed to read ${_CONFIG} configuration file"
if [[ -z "${_KERNEL}" ]]; then
    echo "Trying to autodetect ${_RUNNING_ARCH} kernel..."
    [[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _KERNEL="/usr/lib/modules/*/vmlinuz"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KERNEL="/boot/Image.gz"
fi
# allow * in config
#shellcheck disable=SC2116,2086
_KERNEL="$(echo ${_KERNEL})"
if [[ ! -f "${_KERNEL}" ]]; then
    _abort "kernel image does not exist!"
fi
_KERNELVERSION="$(_kver "${_KERNEL}")"
_MODULE_DIR="/lib/modules/${_KERNELVERSION}"
[[ -d "${_MODULE_DIR}" ]] || _abort "${_MODULE_DIR} is not a valid kernel module directory!"
_BUILD_DIR="$(_init_rootfs "${_KERNELVERSION}" "${_TARGET_DIR}")" || exit 1
_ROOTFS="${_TARGET_DIR:-${_BUILD_DIR}/root}"
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    echo "Starting build: ${_GENERATE_IMAGE}"
elif [[ -n "${_TARGET_DIR}" ]]; then
    echo "Starting build directory: ${_TARGET_DIR}"
else
    echo "Starting dry run..."
fi
if (( ${#_HOOKS[*]} == 0 )); then
    _abort "No hooks found in config file!"
fi
echo "Using kernel: ${_KERNEL}"
echo "Detected kernel version: ${_KERNELVERSION}"
_builtin_modules
_HOOK_COUNT=1
_HOOKS_END_COUNT="$(echo "${_HOOKS[@]}" | wc -w)"
if [[ "${_HOOKS_END_COUNT}" -lt 10 ]]; then
    _ADD_ZERO=""
else
    _ADD_ZERO=1
fi
echo "Running ${_HOOKS_END_COUNT} hooks..."
for i in "${_HOOKS[@]}"; do
    if [[ -n "${_ADD_ZERO}" && "${_HOOK_COUNT}" -lt 10 ]]; then
        echo "0${_HOOK_COUNT}/${_HOOKS_END_COUNT}: ${i}"
    else
        echo "${_HOOK_COUNT}/${_HOOKS_END_COUNT}: ${i}"
    fi
    _run_hook "${i}"
    _HOOK_COUNT="$((_HOOK_COUNT+1))"
done
_install_libs
_install_modules "${!_MOD_PATH[@]}"
ldconfig -r "${_ROOTFS}" &>"${_NO_LOG}" || exit 1
# remove /var/cache/ldconfig/aux-cache for reproducibility
rm -f -- "${_ROOTFS}/var/cache/ldconfig/aux-cache"
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    _create_cpio "${_GENERATE_IMAGE}" "${_COMP}" || exit 1
    _cleanup
    echo "Build complete."
elif [[ -n "${_TARGET_DIR}" ]]; then
    _cleanup
    echo "Build directory complete."
else
    _cleanup
    echo "Dry run complete."
fi
# vim: set ft=sh ts=4 sw=4 et:
