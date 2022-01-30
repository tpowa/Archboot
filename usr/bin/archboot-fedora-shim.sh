#!/bin/bash
_FEDORA_SERVER="https://kojipkgs.fedoraproject.org"
_SHIM_VERSION="15.4"
_SHIM_RELEASE="5"
_SHIM_URL="${_FEDORA_SERVER}/packages/shim/${_SHIM_VERSION}/${_SHIM_RELEASE}"
_SHIM_RPM="x86_64/shim-x64-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM32_RPM="x86_64/shim-ia32-${_SHIM_VERSION}-${_SHIM_RELEASE}.x86_64.rpm"
_SHIM_AA64_RPM="aarch64/shim-aa64-${_SHIM_VERSION}-${_SHIM_RELEASE}.aarch64.rpm"
_SHIM=$(mktemp -d shim.XXXX)
_SHIM32=$(mktemp -d shim32.XXXX)
_SHIMAA64=$(mktemp -d shimaa64.XXXX)
_USER="tobias"
_GROUP="users"
_GPG="--detach-sign --no-armor --batch --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"
_SERVER="pkgbuild.com"
_SHIM_ARCH_SERVERDIR="/home/tpowa/public_html/archboot-helper/fedora-shim"

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi
### check for tpowa's build server
if [[ ! "$(cat /etc/hostname)" == "T-POWA-LX" ]]; then
    echo "This script should only be run on tpowa's build server. Aborting..."
    exit 1
fi
# download packages from fedora server
echo "Downloading fedora shim..."
curl -s --create-dirs -L -O --output-dir "${_SHIM}" ${_SHIM_URL}/${_SHIM_RPM} || exit 1
curl -s --create-dirs -L -O --output-dir "${_SHIM32}" ${_SHIM_URL}/${_SHIM32_RPM} || exit 1
curl -s --create-dirs -L -O --output-dir "${_SHIMAA64}" ${_SHIM_URL}/${_SHIM_AA64_RPM} || exit 1
# unpack rpm
echo "Unpacking roms ..."
bsdtar -C "${_SHIM}" -xf "${_SHIM}"/*.rpm
bsdtar -C "${_SHIM32}" -xf "${_SHIM32}"/*.rpm
bsdtar -C "${_SHIMAA64}" -xf "${_SHIMAA64}"/*.rpm 
echo "Copy shim files ..."
mkdir -m 777 shim-fedora
cp "${_SHIM}"/boot/efi/EFI/fedora/{mmx64.efi,shimx64.efi} shim-fedora/
cp "${_SHIM}/boot/efi/EFI/fedora/shimx64.efi" shim-fedora/BOOTX64.efi
cp "${_SHIM32}"/boot/efi/EFI/fedora/{mmia32.efi,shimia32.efi} shim-fedora/
cp "${_SHIM32}/boot/efi/EFI/fedora/shimia32.efi" shim-fedora/BOOTIA32.efi
cp "${_SHIMAA64}"/boot/efi/EFI/fedora/{mmaa64.efi,shimaa64.efi} shim-fedora/
cp "${_SHIMAA64}/boot/efi/EFI/fedora/shimaa64.efi" shim-fedora/BOOTAA64.efi
# cleanup
echo "Cleanup directories ${_SHIM} ${_SHIM32} ${_SHIMAA64} ..."
rm -r "${_SHIM}" "${_SHIM32}" "${_SHIMAA64}"
# sign files
echo "Sign files and upload ..."
#shellcheck disable=SC2086
cd shim-fedora/ || exit 1
chown "${_USER}" ./*
chgrp "${_GROUP}" ./*
for i in *.efi; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}" || exit 1
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
sudo -u "${_USER}" scp ./* "${_SERVER}:${_SHIM_ARCH_SERVERDIR}" || exit 1
# cleanup
echo "Remove fedora-shim directory."
cd ..
rm -r shim-fedora
echo "Finished fedora Shim."
