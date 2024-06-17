#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/container.sh
_ISO_BUILD_DIR="$(mktemp -d "${_ISO_HOME_ARCH}"/server-release.XXX)"

_update_pacman_chroot() {
    if [[ "${_ARCH}" == "aarch64" ]]; then
        _ARCH_DIR="${_PACMAN_AARCH64}"
        _ARCH_CHROOT_PUBLIC="${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}"
        _PACMAN_CHROOT="${_PACMAN_AARCH64_CHROOT}"
        _SERVER_PACMAN="${_SERVER_PACMAN_AARCH64}"
    elif [[ "${_ARCH}" == "riscv64" ]]; then
        _ARCH_DIR="${_PACMAN_RISCV64}"
        _ARCH_CHROOT_PUBLIC="${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}"
        _PACMAN_CHROOT="${_PACMAN_RISCV64_CHROOT}"
        _SERVER_PACMAN="${_SERVER_PACMAN_RISCV64}"
    fi
    # update pacman chroot
    cd "${_ISO_HOME}" || exit 1
    [[ -d "${_ARCH_DIR}" ]] || mkdir "${_ARCH_DIR}"
    echo "Downloading pacman ${_ARCH} chroot..."
    [[ -f pacman-${_ARCH}-chroot-latest.tar.zst ]] && rm pacman-"${_ARCH}"-chroot-latest.tar.zst{,.sig} 2>"${_NO_LOG}"
    ${_DLPROG} -O "${_ARCH_CHROOT_PUBLIC}"/"${_PACMAN_CHROOT}"
    ${_DLPROG} -O "${_ARCH_CHROOT_PUBLIC}"/"${_PACMAN_CHROOT}".sig
    # verify download
    #shellcheck disable=SC2024
    gpg --chuid "${_USER}" --verify "${_PACMAN_CHROOT}.sig" &>"${_NO_LOG}" || exit 1
    bsdtar -C "${_ARCH_DIR}" -xf "${_PACMAN_CHROOT}" &>"${_NO_LOG}"
    echo "Removing installation tarball..."
    rm "${_PACMAN_CHROOT}"{,.sig} &>"${_NO_LOG}"
    # update container to latest packages
    echo "Updating container to latest packages..."
    # fix mirrorlist
    [[ "${_ARCH}" == "riscv64" ]] && sed -i -e 's|^#Server = https://riscv|Server = https://riscv|g' \
                                     "${_ARCH_DIR}"/etc/pacman.d/mirrorlist
    ${_NSPAWN} "${_ARCH_DIR}" pacman -Syu --noconfirm &>"${_NO_LOG}" || exit 1
    _fix_network "${_ARCH_DIR}"
    _CLEANUP_CONTAINER="1" _clean_container "${_ARCH_DIR}" &>"${_NO_LOG}"
    _CLEANUP_CACHE="1" _clean_cache "${_ARCH_DIR}" &>"${_NO_LOG}"
    echo "Generating tarball..."
    tar -acf "${_PACMAN_CHROOT}" -C "${_ARCH_DIR}" .
    echo "Removing ${_ARCH_DIR}..."
    rm -r "${_ARCH_DIR}"
    echo "Finished container tarball."
    echo "Sign tarball..."
    #shellcheck disable=SC2046,SC2086,SC2116
    gpg --chuid "${_USER}" $(echo ${_GPG}) "${_PACMAN_CHROOT}" || exit 1
    chown "${_USER}:${_GROUP}" "${_PACMAN_CHROOT}"{,.sig} || exit 1
    echo "Syncing files to ${_SERVER}:${_PUB}/.${_SERVER_PACMAN}..."
    #shellcheck disable=SC2086
    run0 -u "${_USER}" -D "${_ISO_HOME}" ${_RSYNC} "${_PACMAN_CHROOT}"{,.sig} "${_SERVER}:${_PUB}/.${_SERVER_PACMAN}/" || exit 1
}

_server_upload() {
    # copy files to server
    echo "Syncing files to ${_SERVER}:${_PUB}/.${1}/${_ARCH}..."
    #shellcheck disable=SC2086
    run0 -u "${_USER}" ssh "${_SERVER}" "[[ -d "${_PUB}/.${1}/${_ARCH}" ]] || mkdir -p "${_PUB}/.${1}/${_ARCH}""
    #shellcheck disable=SC2086
    run0 -u "${_USER}" -D "${2}" ${_RSYNC} "${_DIR}" "${_SERVER}":"${_PUB}/.${1}/${_ARCH}/" || exit 1
    # move files on server, create symlink and removing ${_PURGE_DATE} old release
    run0 -u "${_USER}" ssh "${_SERVER}" <<EOF
echo "Removing old purge date reached ${_PUB}/.${1}/${_ARCH}/$(date -d "$(date +) - ${_PURGE_DATE}" +%Y.%m) directory..."
rm -r ${_PUB}/".${1}"/"${_ARCH}"/"$(date -d "$(date +) - ${_PURGE_DATE}" +%Y.%m)" 2>"${_NO_LOG}"
cd ${_PUB}/".${1}"/"${_ARCH}"
echo "Creating new latest symlink in ${_PUB}/.${1}/${_ARCH}..."
rm latest
ln -s "${_DIR}" latest
EOF
    # create autoindex HEADER.html
    run0 -u "${_USER}" ssh "${_SERVER}" "[[ -e ~/lsws-autoindex.sh ]] && ~/./lsws-autoindex.sh"
}

_create_archive() {
    [[ -d "archive" ]] || mkdir archive
    [[ -d "archive/${_DIR}" ]] && rm -r "archive/${_DIR}"
    [[ -d "${_DIR}" ]] && mv "${_DIR}" archive/
}

# sign files and create new b2sum.txt
_sign_b2sum() {
    for i in $1; do
        if [[ -f "${i}" ]]; then
            #shellcheck disable=SC2046,SC2086,SC2116
            gpg --chuid "${_USER}" $(echo ${_GPG}) "${i}"
            cksum -a blake2b "${i}" >> b2sum.txt
        fi
        if [[ -f "${i}.sig" ]]; then
            cksum -a blake2b "${i}.sig" >> b2sum.txt
        fi
    done
}

_update_source() {
    cd "${_ISO_HOME_SOURCE}" || exit 1
    _create_archive
    echo "Creating ${_ARCH} archboot repository..."
    "archboot-${_ARCH}-create-repository.sh" "${_DIR}" || exit 1
    chown -R "${_USER}:${_GROUP}" "${_DIR}"
    _server_upload "${_SERVER_SOURCE_DIR}" "${_ISO_HOME_SOURCE}"
}

_server_release() {
    cd "${_ISO_HOME_ARCH}" || exit 1
    "archboot-${_ARCH}-release.sh" "${_ISO_BUILD_DIR}" "${_ARCHBOOT_SOURCE}/${_ARCH}/${_DIR}" || exit 1
    # set user rights on files
    [[ -d "${_ISO_BUILD_DIR}" ]] || exit 1
    chmod 755 "${_ISO_BUILD_DIR}"
    chown -R "${_USER}:${_GROUP}" "${_ISO_BUILD_DIR}"
    cd "${_ISO_BUILD_DIR}" || exit 1
    # removing b2sum
    rm b2sum.txt
    _sign_b2sum "*"
    for i in boot iso img uki; do
        [[ -d ${i} ]] && _sign_b2sum "${i}/*"
    done
    chown -R "${_USER}:${_GROUP}" ./*
    cd ..
    _create_archive
    mv "${_ISO_BUILD_DIR}" "${_DIR}"
    _server_upload "${_SERVER_IMAGE_DIR}" "${_ISO_HOME_ARCH}"
}
# vim: set ft=sh ts=4 sw=4 et:
