#! /bin/bash
_DIRECTORY="$(date +%Y.%m)"
_ARCH="aarch64"
_BUILDDIR="/home/tobias/Arch/iso/${_ARCH}"
_SERVER="pkgbuild.com"
_SERVER_HOME="/home/tpowa/"
_SERVER_DIR="/home/tpowa/public_html/archboot-images"
_USER="tobias"
_GROUP="users"
_GPG="--detach-sign --batch --passphrase-file /etc/archboot/gpg.passphrase --pinentry-mode loopback -u 7EDF681F"
_PACMAN_AARCH__BUILDDIR="/home/tobias/Arch/iso"
_PACMAN_AARCH_SERVERDIR="/home/tpowa/public_html/archboot-helper/pacman-chroot-aarch64"
_PACMAN_AARCH64="pacman-aarch64-chroot"
_PACMAN_AARCH64_CHROOT_SERVER="https://pkgbuild.com/~tpowa/archboot-helper/pacman-chroot-aarch64"
_PACMAN_AARCH64_CHROOT="pacman-aarch64-chroot-latest.tar.zst"

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
# update aarch64 pacman chroot
cd "${_PACMAN_AARCH__BUILDDIR}"
mkdir "${_PACMAN_AARCH64}"
echo "Downloading archlinuxarm pacman aarch64 chroot..."
[[ -f pacman-aarch64-chroot-latest.tar.zst ]] && rm pacman-aarch64-chroot-latest.tar.zst{,.sig}
wget ${_PACMAN_AARCH64_CHROOT_SERVER}/${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
# verify dowload
sudo -u "${_USER}" gpg --verify "${_PACMAN_AARCH64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
bsdtar -C "${_PACMAN_AARCH64}" -xf "${_PACMAN_AARCH64_CHROOT}" >/dev/null 2>&1
echo "Removing installation tarball ..."
rm ${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
# update container to latest packages
echo "Update container to latest packages..."
systemd-nspawn -D "${_PACMAN_AARCH64}" pacman -Syu --noconfirm >/dev/null 2>&1
# remove package cache
echo "Remove package cache from container ..."
systemd-nspawn -D "${_PACMAN_AARCH64}" pacman -Scc --noconfirm >/dev/null 2>&1
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_PACMAN_AARCH64}"/etc/pacman.conf
# fix network in container
rm "${_PACMAN_AARCH64}/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "${_PACMAN_AARCH64}/etc/resolv.conf"
echo "Clean container, delete not needed files from ${_PACMAN_AARCH64} ..."
rm -r "${_PACMAN_AARCH64}"/usr/include >/dev/null 2>&1
rm -r "${_PACMAN_AARCH64}"/usr/share/{man,doc,info,locale} >/dev/null 2>&1
echo "Generating tarball ..."
tar -acf "${_PACMAN_AARCH64_CHROOT}" -C "${_PACMAN_AARCH64}" .
echo "Removing ${_PACMAN_AARCH64} ..."
rm -r "${_PACMAN_AARCH64}"
echo "Finished container tarball."
sudo -u "${_USER}" gpg ${_GPG} "${_PACMAN_AARCH64_CHROOT}"
chown "${_USER}" ${_PACMAN_AARCH64_CHROOT}{,.sig}
chgrp "${_GROUP}" ${_PACMAN_AARCH64_CHROOT}{,.sig}
sudo -u "${_USER}" scp ${_PACMAN_AARCH64_CHROOT}{,.sig} ${_SERVER}:${_PACMAN_AARCH_SERVERDIR}
# create release in "${_BUILDDIR}"
cd "${_BUILDDIR}"
[[ -e "${_DIRECTORY}" ]] && rm -r "${_DIRECTORY}"
archboot-"${_ARCH}"-release.sh "${_DIRECTORY}" || exit 1
# set user rights on files
chown -R "${_USER}" "${_DIRECTORY}"
chgrp -R "${_GROUP}" "${_DIRECTORY}"
cd "${_DIRECTORY}"
# remove sha256sum and install image
rm sha256sum.txt
# sign files and create new sha256sum.txt
for i in *; do
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
for i in boot/*; do
    [[ -f "${i}" ]] && sudo -u "${_USER}" gpg ${_GPG} "${i}"
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    [[ -f "${i}.sig" ]] && cksum -a sha256 "${i}.sig" >> sha256sum.txt
done
cd ..
# copy files to server
sudo -u "${_USER}" scp -r "${_DIRECTORY}" "${_SERVER}":"${_SERVER_HOME}"
# move files on server, create symlink and remove 3 month old release
sudo -u "${_USER}" ssh "${_SERVER}" <<EOF
rm -r "${_SERVER_DIR}"/"${_ARCH}"/"${_DIRECTORY}"
rm -r "${_SERVER_DIR}"/"${_ARCH}"/"$(date -d "$(date +) - 3 month" +%Y.%m)"
mv "${_DIRECTORY}" "${_SERVER_DIR}"/"${_ARCH}"
cd "${_SERVER_DIR}"/"${_ARCH}"
rm latest
ln -s "${_DIRECTORY}" latest
EOF
