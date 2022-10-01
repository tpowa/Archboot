#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/repository.sh
_ARCHBOOT="archboot-arm"
[[ -d "${1}" ]] || (echo "Create directory ${1} ..."; mkdir "${1}")
_REPODIR="$(mktemp -d "${1}"/repository.XXX)"
_CACHEDIR="${_REPODIR}/var/cache/pacman/pkg"
[[ -z "${1}" ]] && _usage
_root_check
echo "Starting repository creation ..."
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _cachedir_check
    _create_pacman_conf "${_REPODIR}"
    _prepare_pacman "${_REPODIR}" || exit 1
    _download_packages "${_REPODIR}" || exit 1
    _umount_special "${_REPODIR}" || exit 1
fi
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    _pacman_chroot "${_REPODIR}" "${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}" "${_PACMAN_AARCH64_CHROOT}" || exit 1
    _create_pacman_conf "${_REPODIR}" "use_container_config"
    _other_download_packages "${_REPODIR}" || exit 1
fi
_move_packages "${_REPODIR}" "${1}" || exit 1
_cleanup_repodir "${_REPODIR}" || exit 1
_create_archboot_db "${1}" || exit 1
echo "Finished repository creation in ${_REPODIR} ."

