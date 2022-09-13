#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/repository.sh
_ARCHBOOT="archboot-riscv"
[[ -d "${1}" ]] || (echo "Create directory ${1} ..."; mkdir "${1}")
_REPODIR="$(mktemp -d "${1}"/repository.XXX)"
_CACHEDIR="${_REPODIR}/var/cache/pacman/pkg"
[[ -z "${1}" ]] && _usage
_root_check
_cachedir_check
echo "Starting repository creation ..."
if [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
    _create_pacman_conf "${_REPODIR}"
    _prepare_pacman "${_REPODIR}" || exit 1
    _download_packages "${_REPODIR}" || exit 1
    _umount_special "${_REPODIR}" || exit 1
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _riscv64_pacman_chroot "${_REPODIR}" || exit 1
    _create_pacman_conf "${_REPODIR}" "use_container_config"
    _other_download_packages "${_REPODIR}" || exit 1
fi
_move_packages "${_REPODIR}" "${1}" || exit 1
_cleanup_repodir "${_REPODIR}" || exit 1
_create_archboot_db "${1}" || exit 1
echo "Finished repository creation in ${_REPODIR} ."

