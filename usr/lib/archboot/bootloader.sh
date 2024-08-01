#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
# fedora shim setup
_SHIM_VERSION="15.8"
_SHIM_RELEASE="3"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/${_SHIM_VERSION}/${_SHIM_RELEASE}"
_SHIM_RPM="x86_64/shim-x64-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM32_RPM="x86_64/shim-ia32-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM_AA64_RPM="aarch64/shim-aa64-${_SHIM_VERSION}-${_SHIM_RELEASE}.aarch64.rpm"
_ARCH_SERVERDIR="/${_PUB}/src/bootloader"
_GRUB_ISO="/usr/share/archboot/grub/archboot-iso-grub.cfg"

_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Bootloader\e[m"
    echo -e "\e[1m----------------\e[m"
    echo "Upload bootloaders to archboot server."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}

_grub_mkstandalone() {
    #shellcheck disable=SC2086
    ${1} ${2} grub-mkstandalone -d "/usr/lib/grub/${_GRUB_ARCH}" -O "${_GRUB_ARCH}" \
    --sbat=/usr/share/grub/sbat.csv --fonts=ter-u16n --locales="" --themes="" \
    -o "grub-efi/${_GRUB_EFI}" "boot/grub/grub.cfg=${_GRUB_ISO}"
}

_prepare_shim_files () {
    # download packages from fedora server
    echo "Downloading fedora shim..."
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIM}" ${_SHIM_URL}/${_SHIM_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIM32}" ${_SHIM_URL}/${_SHIM32_RPM} || exit 1
    ${_DLPROG} --create-dirs -L -O --output-dir "${_SHIMAA64}" ${_SHIM_URL}/${_SHIM_AA64_RPM} || exit 1
    # unpack rpm
    echo "Unpacking rpms..."
    bsdtar -C "${_SHIM}" -xf "${_SHIM}"/*.rpm
    bsdtar -C "${_SHIM32}" -xf "${_SHIM32}"/*.rpm
    bsdtar -C "${_SHIMAA64}" -xf "${_SHIMAA64}"/*.rpm 
    echo "Copying shim files..."
    mkdir -m 777 shim-fedora
    cp "${_SHIM}"/boot/efi/EFI/fedora/{mmx64.efi,shimx64.efi} shim-fedora/
    cp "${_SHIM}/boot/efi/EFI/fedora/shimx64.efi" shim-fedora/BOOTX64.efi
    cp "${_SHIM32}"/boot/efi/EFI/fedora/{mmia32.efi,shimia32.efi} shim-fedora/
    cp "${_SHIM32}/boot/efi/EFI/fedora/shimia32.efi" shim-fedora/BOOTIA32.efi
    cp "${_SHIMAA64}"/boot/efi/EFI/fedora/{mmaa64.efi,shimaa64.efi} shim-fedora/
    cp "${_SHIMAA64}/boot/efi/EFI/fedora/shimaa64.efi" shim-fedora/BOOTAA64.efi
    # cleanup
    echo "Cleanup directories ${_SHIM} ${_SHIM32} ${_SHIMAA64}..."
    rm -r "${_SHIM}" "${_SHIM32}" "${_SHIMAA64}"
}

# GRUB standalone setup
### build grubXXX with all modules: http://bugs.archlinux.org/task/71382
### See also: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
### RISC64: https://fedoraproject.org/wiki/Architectures/RISC-V/GRUB2
_prepare_uefi_X64() {
    echo "Preparing X64 Grub..."
    _GRUB_ARCH="x86_64-efi"
    _GRUB_EFI="grubx64.efi"
    _grub_mkstandalone
}

_prepare_uefi_IA32() {
    echo "Preparing IA32 Grub..."
    _GRUB_ARCH="i386-efi"
    _GRUB_EFI="grubia32.efi"
    _grub_mkstandalone
}

_prepare_uefi_AA64() {
    echo "Installing grub package..."
    ${_NSPAWN} "${1}" pacman -Sy grub --noconfirm
    echo "Preparing AA64 Grub..."
    _GRUB_ARCH="arm64-efi"
    _GRUB_EFI="grubaa64.efi"
    mkdir "${1}"/grub-efi
    #shellcheck disable=SC2086
    _grub_mkstandalone "${_NSPAWN}" "${1}"
    mv "${1}/grub-efi/${_GRUB_EFI}" grub-efi/
}

_prepare_uefi_RISCV64() {
    echo "Installing grub package..."
    ${_NSPAWN} "${1}" pacman -Sy grub --noconfirm
    echo "Preparing RISCV64 Grub..."
    _GRUB_ARCH="riscv64-efi"
    _GRUB_EFI="grubriscv64.efi"
    mkdir "${1}"/grub-efi
    #shellcheck disable=SC2086
    _grub_mkstandalone "${_NSPAWN}" "${1}"
    mv "${1}/grub-efi/${_GRUB_EFI}" grub-efi/
}

_upload_efi_files() {
    # sign files
    echo "Sign files and upload..."
    #shellcheck disable=SC2086
    cd ${1}/ || exit 1
    chmod 644 ./*
    chown "${_USER}:${_GROUP}" ./*
    for i in *.efi; do
        #shellcheck disable=SC2086
        if [[ -f "${i}" ]]; then
            #shellcheck disable=SC2046,SC2086,SC2116
            gpg --chuid "${_USER}" $(echo ${_GPG}) "${i}" || exit 1
        fi
    done
    #shellcheck disable=SC2086
    run0 -u "${_USER}" -D ./ ${_RSYNC} ./* "${_SERVER}:.${_ARCH_SERVERDIR}/" || exit 1
    cd ..
}

_cleanup() {
echo "Removing ${1} directory."
rm -r "${1}"
echo "Finished ${1}."
}
# vim: set ft=sh ts=4 sw=4 et:
