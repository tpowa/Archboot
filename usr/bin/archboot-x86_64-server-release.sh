#! /bin/bash
_DIRECTORY="$(date +%Y.%m)"
_ARCH="x86_64"
_ISODIR="/home/tobias/Arch/iso/${_ARCH}"
_BUILDDIR="$(mktemp -d ${_ISODIR}/server-release.XXX)"
_PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
_PACMAN_CONF="/etc/pacman.conf"
_SERVER="pkgbuild.com"
_SERVER_HOME="/home/tpowa/"
_SERVER_DIR="/home/tpowa/public_html/archboot-images"
_USER="tobias"
_GROUP="users"
_GPG="--detach-sign --batch --no-armor --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"

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

# use pacman.conf with disabled [testing] repository
cp "${_PACMAN_CONF}" "${_PACMAN_CONF}".old
cp "${_PACMAN_CONF}".archboot "${_PACMAN_CONF}"
# use mirrorlist with enabled rackspace mirror
cp "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}".old
cp "${_PACMAN_MIRROR}".archboot "${_PACMAN_MIRROR}"
# create release in "${_ISODIR}"
cd "${_ISODIR}" || exit 1
"archboot-${_ARCH}-release.sh" "${_BUILDDIR}" ||\
(rm -r "${_BUILDDIR}"; cp "${_PACMAN_MIRROR}".old "${_PACMAN_MIRROR}";\
cp "${_PACMAN_CONF}".old "${_PACMAN_CONF}"; exit 1)
# restore pacman.conf and mirrorlist
cp "${_PACMAN_MIRROR}".old "${_PACMAN_MIRROR}"
cp "${_PACMAN_CONF}".old "${_PACMAN_CONF}"
# set user rights on files
[[ -d "${_BUILDDIR}"  ]] && exit 1
chmod 755 "${_BUILDDIR}"
chown -R "${_USER}" "${_BUILDDIR}"
chgrp -R "${_GROUP}" "${_BUILDDIR}"
cd "${_BUILDDIR}" || exit 1
# remove sha256sum
rm sha256sum.txt
# sign files and create new sha256sum.txt
for i in *; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
for i in boot/*; do
    #shellcheck disable=SC2086
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
cd ..
[[ -d "archive" ]] || mkdir archive
[[ -d "archive/${_DIRECTORY}" ]] && rm -r "archive/${_DIRECTORY}"
[[ -d "${_DIRECTORY}" ]] && mv "${_DIRECTORY}" archive/
mv "${_BUILDDIR}" "${_DIRECTORY}"
# copy files to server
sudo -u "${_USER}" scp -r "${_DIRECTORY}" "${_SERVER}":"${_SERVER_HOME}" || exit 1
# move files on server, create symlink and remove 3 month old release
sudo -u "${_USER}" ssh "${_SERVER}" <<EOF
rm -r "${_SERVER_DIR}"/"${_ARCH}"/"${_DIRECTORY}"
rm -r "${_SERVER_DIR}"/"${_ARCH}"/"$(date -d "$(date +) - 3 month" +%Y.%m)"
mv "${_DIRECTORY}" "${_SERVER_DIR}"/"${_ARCH}"
cd "${_SERVER_DIR}"/"${_ARCH}"
rm latest
ln -s "${_DIRECTORY}" latest
EOF
