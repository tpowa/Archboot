#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# archboot-cpio.sh - modular tool for building initramfs images
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

. /usr/lib/archboot/common.sh
. /usr/lib/archboot/cpio/cpio.sh
if [[ -z "${1}" ]]; then
    _usage
fi
_root_check
_parameters "$@"
#shellcheck disable=SC1090
. "${_CONFIG}" 2>"${_NO_LOG}" || _abort "Failed to read ${_CONFIG} configuration file"
echo "Using config: ${_CONFIG}"
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
_MOD_DIR="/lib/modules/${_KERNELVERSION}"
[[ -d "${_MOD_DIR}" ]] || _abort "${_MOD_DIR} is not a valid kernel module directory!"
_ALL_MODS="$(sd '^' "${_MOD_DIR}/" < "${_MOD_DIR}"/modules.order)"
_BUILD_DIR="$(_init_rootfs "${_KERNELVERSION}" "${_TARGET_DIR}")" || exit 1
_ROOTFS="${_TARGET_DIR:-${_BUILD_DIR}/root}"
if (( ${#_HOOKS[*]} == 0 )); then
    _abort "No hooks found in config file!"
fi
echo "Using kernel: ${_KERNEL}"
echo "Detected kernel version: ${_KERNELVERSION}"
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    echo "Starting build: ${_GENERATE_IMAGE}"
elif [[ -n "${_TARGET_DIR}" ]]; then
    echo "Starting build directory: ${_TARGET_DIR}"
else
    echo "Starting dry run..."
fi
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
if [[ -z "${_FILES[*]}" ]]; then
    echo "Skipping files..."
else
    echo "Adding files..."
    _install_files
fi
_install_libs
if [[ -z "${_MODS[*]}" && -z "${_MOD_DEPS[*]}" ]]; then
    echo "Skipping kernel modules..."
else
    echo "Adding kernel modules..."
    _install_mods
fi
systemd-sysusers --root "${_ROOTFS}" &>"${_NO_LOG}"
ldconfig -r "${_ROOTFS}" &>"${_NO_LOG}" || exit 1
# remove /var/cache/ldconfig/aux-cache for reproducibility
rm -f -- "${_ROOTFS}/var/cache/ldconfig/aux-cache"
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    _cpio_fw
    _create_cpio "${_ROOTFS}" "${_GENERATE_IMAGE}" || exit 1
    _cleanup
elif [[ -n "${_TARGET_DIR}" ]]; then
    _cpio_fw
    _cleanup
    echo "Build directory complete."
else
    _cleanup
    echo "Dry run complete."
fi
