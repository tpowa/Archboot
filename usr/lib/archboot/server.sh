#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/container.sh
_ISO_BUILD_DIR="$(mktemp -d "${_ISO_HOME_ARCH}"/server-release.XXX)"

_update_aarch64_pacman_chroot() {
    # update aarch64 pacman chroot
    cd "${_ISO_HOME}" || exit 1
    [[ -d "${_PACMAN_AARCH64}" ]] || mkdir "${_PACMAN_AARCH64}"
    echo "Downloading archlinuxarm pacman aarch64 chroot..."
    [[ -f pacman-aarch64-chroot-latest.tar.zst ]] && rm pacman-aarch64-chroot-latest.tar.zst{,.sig} 2>/dev/null
    wget ${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}/${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
    # verify download
    sudo -u "${_USER}" gpg --verify "${_PACMAN_AARCH64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${_PACMAN_AARCH64}" -xf "${_PACMAN_AARCH64_CHROOT}" >/dev/null 2>&1
    echo "Removing installation tarball ..."
    rm ${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
    # update container to latest packages
    echo "Update container to latest packages..."
    systemd-nspawn -D "${_PACMAN_AARCH64}" pacman -Syu --noconfirm >/dev/null 2>&1 || exit 1
    _fix_network "${_PACMAN_AARCH64}"
    _CLEANUP_CONTAINER="1" _clean_container "${_PACMAN_AARCH64}" >/dev/null 2>&1
    _CLEANUP_CACHE="1" _clean_cache "${_PACMAN_AARCH64}" >/dev/null 2>&1
    echo "Generating tarball ..."
    tar -acf "${_PACMAN_AARCH64_CHROOT}" -C "${_PACMAN_AARCH64}" .
    echo "Removing ${_PACMAN_AARCH64} ..."
    rm -r "${_PACMAN_AARCH64}"
    echo "Finished container tarball."
    echo "Sign tarball ..."
    #shellcheck disable=SC2086
    sudo -u "${_USER}" gpg ${_GPG} "${_PACMAN_AARCH64_CHROOT}" || exit 1
    chown "${_USER}:${_GROUP}" ${_PACMAN_AARCH64_CHROOT}{,.sig} || exit 1
    echo "Uploading files to ${_SERVER}:${_SERVER_PACMAN_AARCH64} ..."
    sudo -u "${_USER}" scp -q ${_PACMAN_AARCH64_CHROOT}{,.sig} ${_SERVER}:${_SERVER_PACMAN_AARCH64} || exit 1
}

_update_riscv64_pacman_chroot() {
    # update riscv64 pacman chroot
    cd "${_ISO_HOME}" || exit 1
    [[ -d "${_PACMAN_RISCV64}" ]] || mkdir "${_PACMAN_RISCV64}"
    echo "Downloading archlinuxarm pacman RISCV64 chroot..."
    [[ -f pacman-riscv64-chroot-latest.tar.zst ]] && rm pacman-riscv64-chroot-latest.tar.zst{,.sig} 2>/dev/null
    wget ${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}/${_PACMAN_RISCV64_CHROOT}{,.sig} >/dev/null 2>&1
    # verify download
    sudo -u "${_USER}" gpg --verify "${_PACMAN_RISCV64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${_PACMAN_RISCV64}" -xf "${_PACMAN_RISCV64_CHROOT}" >/dev/null 2>&1
    echo "Removing installation tarball ..."
    rm ${_PACMAN_RISCV64_CHROOT}{,.sig} >/dev/null 2>&1
    # update container to latest packages
    echo "Update container to latest packages..."
    systemd-nspawn -D "${_PACMAN_RISCV64}" pacman -Syu --noconfirm >/dev/null 2>&1 || exit 1
    _fix_network "${_PACMAN_RISCV64}"
    _CLEANUP_CONTAINER="1" _clean_container "${_PACMAN_RISCV64}" >/dev/null 2>&1
    _CLEANUP_CACHE="1" _clean_cache "${_PACMAN_RISCV64}" >/dev/null 2>&1
    echo "Generating tarball ..."
    tar -acf "${_PACMAN_RISCV64_CHROOT}" -C "${_PACMAN_RISCV64}" .
    echo "Removing ${_PACMAN_RISCV64} ..."
    rm -r "${_PACMAN_RISCV64}"
    echo "Finished container tarball."
    echo "Sign tarball ..."
    #shellcheck disable=SC2086
    sudo -u "${_USER}" gpg ${_GPG} "${_PACMAN_RISCV64_CHROOT}" || exit 1
    chown "${_USER}:${_GROUP}" ${_PACMAN_RISCV64_CHROOT}{,.sig} || exit 1
    echo "Uploading files to ${_SERVER}:${_SERVER_PACMAN_RISCV64} ..."
    sudo -u "${_USER}" scp -q ${_PACMAN_RISCV64_CHROOT}{,.sig} ${_SERVER}:${_SERVER_PACMAN_RISCV64} || exit 1
}

_server_upload() {
    # copy files to server
    echo "Uploading files to ${_SERVER}:${_SERVER_HOME}/${_ARCH} ..."
    #shellcheck disable=SC2086
    sudo -u "${_USER}" ssh "${_SERVER}" "[[ -d "${_SERVER_HOME}/${_ARCH}" ]] || mkdir -p ${_SERVER_HOME}/${_ARCH}"
    sudo -u "${_USER}" scp -q -r "${_DIR}" "${_SERVER}":"${_SERVER_HOME}/${_ARCH}" || exit 1
    # move files on server, create symlink and remove ${_PURGE_DATE} old release
    sudo -u "${_USER}" ssh "${_SERVER}" <<EOF
echo "Remove old ${1}/${_ARCH}/${_DIR} directory ..."
rm -r "${1}"/"${_ARCH}"/"${_DIR}"
echo "Remove old purge date reached ${1}/${_ARCH}/$(date -d "$(date +) - ${_PURGE_DATE}" +%Y.%m) directory ..."
rm -r "${1}"/"${_ARCH}"/"$(date -d "$(date +) - ${_PURGE_DATE}" +%Y.%m)" 2>/dev/null
echo "Move ${_ARCH}/${_DIR} to ${1}/${_ARCH} ..."
mv "${_ARCH}/${_DIR}" "${1}"/"${_ARCH}"
echo "Remove ${_SERVER_HOME}/${_ARCH} directory ..."
rm -r "${_SERVER_HOME}/${_ARCH}"
cd "${1}"/"${_ARCH}"
echo "Create new latest symlink in ${1}/${_ARCH} ..."
rm latest
ln -s "${_DIR}" latest
EOF
}

_create_archive() {
    [[ -d "archive" ]] || mkdir archive
    [[ -d "archive/${_DIR}" ]] && rm -r "archive/${_DIR}"
    [[ -d "${_DIR}" ]] && mv "${_DIR}" archive/
}

# sign files and create new sha256sum.txt
_sign_sha256sum() {
    for i in $1; do
        #shellcheck disable=SC2086
        [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}"
        [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
        [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
    done
}

_update_source() {
    cd "${_ISO_HOME_SOURCE}" || exit 1
    _create_archive
    echo "Creating ${_ARCH} archboot repository ..."
    "archboot-${_ARCH}-create-repository.sh" "${_DIR}" || exit 1
    chown -R "${_USER}:${_GROUP}" "${_DIR}"
    _server_upload "${_SERVER_SOURCE_DIR}"
}

_server_release() {
    cd "${_ISO_HOME_ARCH}" || exit 1
    "archboot-${_ARCH}-release.sh" "${_ISO_BUILD_DIR}" "${_ARCHBOOT_SOURCE}/${_ARCH}/${_DIR}" || rm -r "${_ISO_BUILD_DIR}"
    # set user rights on files
    [[ -d "${_ISO_BUILD_DIR}" ]] || exit 1
    chmod 755 "${_ISO_BUILD_DIR}"
    chown -R "${_USER}:${_GROUP}" "${_ISO_BUILD_DIR}"
    cd "${_ISO_BUILD_DIR}" || exit 1
    # remove sha256sum
    rm sha256sum.txt
    _sign_sha256sum "*"
    _sign_sha256sum "boot/*"
    chown -R "${_USER}:${_GROUP}" ./*
    cd ..
    _create_archive
    mv "${_ISO_BUILD_DIR}" "${_DIR}"
    _server_upload "${_SERVER_IMAGE_DIR}"
}
