#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
echo "Starting container creation..."
[[ -d "${1}" ]] || (echo "Creating directory ${1}..."; mkdir "${1}")
if echo "${_BASENAME}" | rg -qw "${_RUNNING_ARCH}"; then
    # running system = creating system
    _cachedir_check
    _create_pacman_conf "${1}"
    _prepare_pacman "${1}" || exit 1
    _pacman_parameters "${1}"
    _install_base_packages "${1}" || exit 1
    _clean_cache "${1}"
    _install_archboot "${1}" || exit 1
    _umount_special "${1}" || exit 1
    _clean_cache "${1}"
    _clean_container "${1}"
    _generate_keyring "${1}" || exit 1
    _copy_mirrorlist_and_pacman_conf "${1}"
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _copy_archboot_defaults "${1}"
        # enable [*-testing] if enabled in host
        if rg -q "^\[core-testing" /etc/pacman.conf; then
            echo "Enable [core-testing] and [extra-testing] repository in container..."
            #shellcheck disable=SC2016
            sd '^#(\[[c,e].*-testing\]\n)#' '$1' "${1}/etc/pacman.conf"
        fi
    fi
else
    # running system != creating system
    if [[ "${_RUNNING_ARCH}" == "x86_64"  ]]; then
        if echo "${_BASENAME}" | rg -qw 'aarch64'; then
            _pacman_container "${1}" "${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}" \
                           "${_ISO_HOME}/${_PACMAN_AARCH64_CHROOT}" || exit 1
        fi
        if echo "${_BASENAME}" | rg -qw 'riscv64'; then
            _pacman_container "${1}" "${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}" \
                           "${_ISO_HOME}/${_PACMAN_RISCV64_CHROOT}" || exit 1
        fi
        _create_pacman_conf "${1}" "use_binfmt"
        _pacman_parameters "${1}" "use_binfmt"
        _install_base_packages "${1}" "use_binfmt" || exit 1
        _install_archboot "${1}" "use_binfmt" || exit 1
        _clean_container "${1}" 2>"${_NO_LOG}"
    else
        echo "Error: binfmt usage is only supported on x86_64!"
        exit 1
    fi
fi
_change_pacman_conf "${1}" || exit 1
_reproducibility "${1}"
_set_hostname "${1}" || exit 1
_ssh_keys "${1}" || exit 1
echo "Finished container setup in ${1}."
# vim: set ft=sh ts=4 sw=4 et:
