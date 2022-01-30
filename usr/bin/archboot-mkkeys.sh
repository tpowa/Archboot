#!/bin/bash
_MKKEYS_SERVER="https://www.rodsbooks.com/efi-bootloaders"
_MKKEYS_URL="${_MKKEYS_SERVER}/mkkeys.sh"
_USER="tobias"
_GROUP="users"
_GPG="--detach-sign --no-armor --batch --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"
_SERVER="pkgbuild.com"
_MKKEYS_ARCH_SERVERDIR="/home/tpowa/public_html/archboot-helper/mkkeys"

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
echo "Downloading mkkeys.sh..."
mkdir -m 777 mkkeys
curl -s --create-dirs -L -O --output-dir ./mkkeys/ ${_MKKEYS_URL} || exit 1
# sign files
echo "Sign files and upload ..."
#shellcheck disable=SC2086
cd mkkeys/ || exit 1
chown "${_USER}" ./*
chgrp "${_GROUP}" ./*
for i in *; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}" || exit 1
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
sudo -u "${_USER}" scp ./* "${_SERVER}:${_MKKEYS_ARCH_SERVERDIR}" || exit 1
# cleanup
echo "Remove mkkeys directory."
cd ..
rm -r mkkeys
echo "Finished fedora Shim."
