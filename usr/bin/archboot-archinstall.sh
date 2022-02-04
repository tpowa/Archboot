#!/bin/bash
_ARCHINSTALL=$(mktemp -d archinstall.XXX)
_AARCH64_W_DIR="archinstall-aarch64"
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
echo "Building archinstall C version X86_64..."
pacman -Sy nuitka gcc archinstall patchelf --noconfirm
nuitka3 --standalone /usr/bin/archinstall || exit 1
mv archinstall.dist/archinstall ./archinstall.x86_64
#rm -r archinstall.{dist,build}
#archboot-aarch64-create-container.sh "${_AARCH64_W_DIR}"
#systemd-nspawn -q -D "${_AARCH64_W_DIR}" /bin/bash -c "pacman -Sy nuitka gcc archinstall patchelf --noconfirm"; cd /;nuitka3 --standalone /usr/bin/archinstall || exit 1
#mv "${_AARCH64_W_DIR}/archinstall.dist/archinstall" ./archinstall.aarch64
#rm -r "${_AARCH64_W_DIR}"
# sign files
echo "Sign file and upload ..."
chmod 755 ./*
chown "${_USER}:${_GROUP}" ./*
for i in ./*; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}" || exit 1
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
sudo -u "${_USER}" scp ./* "${_SERVER}:${_SHIM_ARCH_SERVERDIR}" || exit 1
# cleanup
echo "Remove ${_ARCHINSTALL} directory."
cd ..
rm -r ${_ARCHINSTALL}
echo "Finished archinstall C version."
