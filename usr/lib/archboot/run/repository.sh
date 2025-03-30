#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/repository.sh
_CACHEDIR="${_REPODIR}${_CACHEDIR}"
[[ -z "${1}" ]] && _usage
_root_check
[[ -d "${1}" ]] || (echo "Creating directory ${1}..."; mkdir "${1}")
_REPODIR="$(mktemp -d "${1}"/repository.XXX)"
echo "Starting repository creation..."
if rg -qw "${_RUNNING_ARCH}" <<< "${_BASENAME}"; then
    # running system = creating system
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] && (_x86_64_pacman_use_default || exit 1)
    _cachedir_check
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] || _create_pacman_conf "${_REPODIR}"
    _prepare_pacman "${_REPODIR}" || exit 1
    _pacman_parameters "${_REPODIR}"
    _download_packages "${_REPODIR}" || exit 1
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] && _x86_64_pacman_restore || exit 1
    _umount_special "${_REPODIR}" || exit 1
else
    # running system != creating system
    if [[ "${_RUNNING_ARCH}" == "x86_64"  ]]; then
        if rg -qw 'aarch64' <<< "${_BASENAME}"; then
            _pacman_container "${_REPODIR}" "${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}" \
                              "${_ISO_HOME}/${_PACMAN_AARCH64_CHROOT}" || exit 1
        fi
        if rg -qw 'riscv64' <<< "${_BASENAME}"; then
            _pacman_container "${_REPODIR}" "${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}" \
                              "${_ISO_HOME}/${_PACMAN_RISCV64_CHROOT}" || exit 1
        fi
        _create_pacman_conf "${_REPODIR}" "use_binfmt"
        _pacman_parameters "${_REPODIR}" "use_binfmt"
        _download_packages "${_REPODIR}" "use_binfmt" || exit 1
    else
        echo "Error: binfmt usage is only supported on x86_64!"
        exit 1
    fi
fi
_move_packages "${_REPODIR}" "${1}" || exit 1
_cleanup_repodir "${_REPODIR}" || exit 1
_create_archboot_db "${1}" || exit 1
echo "Finished repository creation in ${_REPODIR}."
