#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
echo "Starting container creation..."
[[ -d "${1}" ]] || (echo "Creating directory ${1}..."; mkdir "${1}")
if echo "${_BASENAME}" | grep -qw "${_RUNNING_ARCH}"; then
    # running system = creating system
    _cachedir_check
    _create_pacman_conf "${1}"
    _prepare_pacman "${1}" || exit 1
    _pacman_parameters "${1}"
    _install_base_packages "${1}" || exit 1
    _clean_mkinitcpio "${1}"
    _clean_cache "${1}"
    _install_archboot "${1}" || exit 1
    _clean_cache "${1}"
    _umount_special "${1}" || exit 1
    _fix_groups "${1}"
    _clean_container "${1}"
    _generate_keyring "${1}" || exit 1
    _copy_mirrorlist_and_pacman_conf "${1}"
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _copy_archboot_defaults "${1}"
        # enable [testing] if enabled in host
        if grep -q "^\[testing" /etc/pacman.conf; then
            echo "Enable [testing] repository in container..."
            sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${1}/etc/pacman.conf"
            sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${1}/etc/pacman.conf"
            sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${1}/etc/pacman.conf"
        fi
    fi
else
    # running system != creating system
    if [[ "${_RUNNING_ARCH}" == "x86_64"  ]]; then
        if echo "${_BASENAME}" | grep -qw aarch64; then
            _pacman_chroot "${1}" "${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}" "${_PACMAN_AARCH64_CHROOT}" || exit 1
        fi
        if echo "${_BASENAME}" | grep -qw riscv64; then
            _pacman_chroot "${1}" "${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}" "${_PACMAN_RISCV64_CHROOT}" || exit 1
        fi
        _create_pacman_conf "${1}" "use_binfmt"
        _pacman_parameters "${1}" "use_binfmt"
        _install_base_packages "${1}" "use_binfmt" || exit 1
        _install_archboot "${1}" "use_binfmt" || exit 1
        _fix_groups "${1}"
        _clean_mkinitcpio "${1}"
        _clean_container "${1}" 2>/dev/null
    else
        echo "Error: binfmt usage is only supported on x86_64!"
        exit 1
    fi
fi
_change_pacman_conf "${1}" || exit 1
_reproducibility "${1}"
_set_hostname "${1}" || exit 1
echo "Finished container setup in ${1}."
