#!/bin/bash
_ARCHINSTALL=$(mktemp -d archinstall.XXX)
_USER="tobias"
_GROUP="users"
_GPG="--detach-sign --no-armor --batch --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"
_SERVER="pkgbuild.com"
_SHIM_ARCH_SERVERDIR="/home/tpowa/public_html/archboot-helper/archinstall"
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
chown "${_USER}:${_GROUP}" "${_ARCHINSTALL}"
cd "${_ARCHINSTALL}" || exit 1
# download packages from fedora server
echo "Building archinstall C version..."
nuitka3 --standalone /usr/bin/archinstall || exit 1
mv archinstall.dist/archinstall ./
# sign files
echo "Sign file and upload ..."
chmod 755 archinstall
chown "${_USER}:${_GROUP}" archinstall
for i in archinstall; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}" || exit 1
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
sudo -u "${_USER}" scp archinstall "${_SERVER}:${_SHIM_ARCH_SERVERDIR}" || exit 1
# cleanup
echo "Remove ${_ARCHINSTALL} directory."
cd ..
rm -r ${_ARCHINSTALL}
echo "Finished archinstall C version."
