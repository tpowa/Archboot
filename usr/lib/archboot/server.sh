#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/container.sh
_ISO_BUILD_DIR="$(mktemp -d "${_ISO_HOME_ARCH}"/server-release.XXX)"

_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Server Release\e[m"
    echo -e "\e[1m-------------------------\e[m"
    echo "Upload new image to an Archboot server."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}

_update_pacman_container() {
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
    # update pacman container
    cd "${_ISO_HOME}" || exit 1
    [[ -d "${_ARCH_DIR}" ]] || mkdir "${_ARCH_DIR}"
    if ! [[ -f pacman-${_ARCH}-container-latest.tar.zst ]]; then
        echo "Downloading pacman ${_ARCH} container..."
        ${_DLPROG} -O "${_ARCH_CHROOT_PUBLIC}"/"${_PACMAN_CHROOT}"
        ${_DLPROG} -O "${_ARCH_CHROOT_PUBLIC}"/"${_PACMAN_CHROOT}".sig
    else
        echo "Using local pacman ${_ARCH} container..."
    fi
    # verify download
    #shellcheck disable=SC2024
    gpg --chuid "${_USER}" --verify "${_PACMAN_CHROOT}.sig" &>"${_NO_LOG}" || exit 1
    bsdtar -C "${_ARCH_DIR}" -xf "${_PACMAN_CHROOT}" &>"${_NO_LOG}"
    echo "Removing installation tarball..."
    rm "${_PACMAN_CHROOT}"{,.sig} &>"${_NO_LOG}"
    # update container to latest packages
    echo "Updating container to latest packages..."
    # fix mirrorlist
    [[ "${_ARCH}" == "riscv64" ]] && sd '^#Server = https://riscv' 'Server = https://riscv' \
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

_update_source() {
    cd "${_ISO_HOME_SOURCE}" || exit 1
    _create_archive
    echo "Creating ${_ARCH} Archboot repository..."
    "archboot-${_ARCH}-create-repository.sh" "${_DIR}" || exit 1
    chown -R "${_USER}:${_GROUP}" "${_DIR}"
    _server_upload "${_SERVER_SOURCE_DIR}" "${_ISO_HOME_SOURCE}"
}

_server_release() {
    cd "${_ISO_HOME_ARCH}" || exit 1
    # needed else package cache is not reachable on binfmt containers
    "archboot-${_ARCH}-release.sh" "${_ISO_BUILD_DIR}" "file://${_ISO_HOME_SOURCE}/${_DIR}" || exit 1
    # set user rights on files
    [[ -d "${_ISO_BUILD_DIR}" ]] || exit 1
    chmod 755 "${_ISO_BUILD_DIR}"
    chown -R "${_USER}:${_GROUP}" "${_ISO_BUILD_DIR}"
    cd "${_ISO_BUILD_DIR}" || exit 1
     # ipxe symlinks and ipxe sign the symlinks
    if [[ -d "${_CERT_DIR}" ]]; then
        mkdir ipxe
        for i in $(fd -t f -E '*.sig' -E '*.txt' -E 'archboot*' -E 'init-*'); do
            ln -s "../${i}" "ipxe/$(basename ${i})"
            archboot-ipxe-sign.sh ipxe/"$(basename ${i})"
        done
        chown -R "${_USER}:${_GROUP}" ipxe/
    fi
    # sign files and no symlinks
    for i in $(fd -t f -E 'ipxe'); do
        #shellcheck disable=SC2046,SC2086,SC2116
        gpg --chuid "${_USER}" $(echo ${_GPG}) "${i}"
    done
    # recreate and sign b2sums
    rm b2sum.txt
    for i in $(fd -t f -t l); do
        cksum -a blake2b "${i}" >> b2sum.txt
        cksum -a blake2b "${i}.sig" >> b2sum.txt
        chown -R "${_USER}:${_GROUP}" "${i}"
        touch "${i}"
    done
    #shellcheck disable=SC2046,SC2086,SC2116
    gpg --chuid "${_USER}" $(echo ${_GPG}) b2sum.txt
    cd ..
    _create_archive
    mv "${_ISO_BUILD_DIR}" "${_DIR}"
    _server_upload "${_SERVER_IMAGE_DIR}" "${_ISO_HOME_ARCH}"
}
