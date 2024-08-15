#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
# fedora shim setup
_OVMF_VERSION="20240524"
_OVMF_RELEASE="5.fc41"
_OVMF_URL="https://kojipkgs.fedoraproject.org/packages/edk2/${_OVMF_VERSION}/${_OVMF_RELEASE}"
_OVMF_RPM="noarch/edk2-ovmf-${_OVMF_VERSION}-${_OVMF_RELEASE}.noarch.rpm"
_OVMF32_RPM="noarch/edk2-ovmf-ia32-${_OVMF_VERSION}-${_OVMF_RELEASE}.noarch.rpm"
_UBOOT_VERSION="2024.01"
_UBOOT_RELEASE="dfsg-5_all"
_UBOOT_URL="http://ftp.us.debian.org/debian/pool/main/u/u-boot"
_UBOOT_DEB="u-boot-qemu_${_UBOOT_VERSION}+${_UBOOT_RELEASE}.deb"
_ARCH_SERVERDIR="/${_PUB}/src/qemu"

_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Qemu\e[m"
    echo -e "\e[1m---------------\e[m"
    echo "Upload qemu files to an Archboot server."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}

_prepare_files () {
    # download packages from fedora server
    echo "Downloading Fedora OVMF and Debian UBOOT..."
    ${_DLPROG} --create-dirs -L -O --output-dir "${_OVMF}" ${_OVMF_URL}/${_OVMF_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_OVMF32}" ${_OVMF_URL}/${_OVMF32_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_UBOOT}" ${_UBOOT_URL}/${_UBOOT_DEB} || exit 1
    # unpack rpm
    echo "Unpacking rpms/deb..."
    bsdtar -C "${_OVMF}" -xf "${_OVMF}"/*.rpm
    bsdtar -C "${_OVMF32}" -xf "${_OVMF32}"/*.rpm
    bsdtar -C "${_UBOOT}" -xf "${_UBOOT}"/*.deb
    bsdtar -C "${_UBOOT}" -xf "${_UBOOT}"/data.tar.xz
    echo "Copying qemu files..."
    mkdir -m 777 qemu
    cp "${_OVMF}"/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd qemu/OVMF_CODE.secboot_x64.fd
    cp "${_OVMF}"/usr/share/edk2/ovmf/OVMF_VARS.secboot.fd qemu/OVMF_VARS.secboot_x64.fd
    cp "${_OVMF32}"/usr/share/edk2/ovmf-ia32/OVMF_CODE.secboot.fd qemu/OVMF_CODE.secboot_ia32.fd
    cp "${_OVMF32}"/usr/share/edk2/ovmf-ia32/OVMF_VARS.secboot.fd qemu/OVMF_VARS.secboot_ia32.fd
    cp "${_UBOOT}"/usr/lib/u-boot/qemu-riscv64_smode/uboot.elf qemu/uboot.elf
    # cleanup
    echo "Cleanup directories ${_OVMF} ${_OVMF32} ${_UBOOT}..."
    rm -r "${_OVMF}" "${_OVMF32}" "${_UBOOT}"
}

_upload_files() {
    # sign files
    echo "Sign files and upload..."
    #shellcheck disable=SC2086
    cd ${1}/ || exit 1
    chmod 644 ./*
    chown "${_USER}:${_GROUP}" ./*
    for i in *; do
        #shellcheck disable=SC2086
        if [[ -f "${i}" ]]; then
            #shellcheck disable=SC2046,SC2086,SC2116
            gpg --chuid "${_USER}" $(echo ${_GPG}) "${i}" || exit 1
        fi
    done
    chown "${_USER}:${_GROUP}" ./*
    #shellcheck disable=SC2086
    run0 -u "${_USER}" -D ./ ${_RSYNC} ./* "${_SERVER}:.${_ARCH_SERVERDIR}/" || exit 1
    cd ..
}

_cleanup() {
echo "Removing ${1} directory."
rm -r "${1}"
echo "Finished ${1}."
}
