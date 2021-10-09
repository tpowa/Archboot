#! /bin/bash
DIRECTORY="$(date +%Y.%m)"
BUILDDIR="/home/tobias/Arch/iso"
PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
PACMAN_CONF="/etc/pacman.conf"
SERVER="repos.archlinux.org"
HOME="/home/tpowa/"
SERVER_DIR="/srv/ftp/iso/archboot"
USER="tobias"
GROUP="users"

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

cp "${PACMAN_CONF}" "${PACMAN_CONF}".old
cp "${PACMAN_CONF}".archboot "${PACMAN_CONF}"
cp "${PACMAN_MIRROR}" "${PACMAN_MIRROR}".old
cp "${PACMAN_MIRROR}".archboot "${PACMAN_MIRROR}"
cd "${BUILDDIR}"
[[ -e "${DIRECTORY}" ]] && rm -r "${DIRECTORY}"
archboot-x86_64-release.sh "${DIRECTORY}"
chown -R "${USER}" "${DIRECTORY}"
chgrp -R "${GROUP}" "${DIRECTORY}"
cp "${PACMAN_MIRROR}".old "${PACMAN_MIRROR}"
cp "${PACMAN_CONF}".old "${PACMAN_CONF}"
sudo -u "${USER}" scp -r "${DIRECTORY}" "${SERVER}":"${HOME}"
sudo -u "${USER}" ssh "${SERVER}" <<EOF
rm -r "${SERVER_DIR}"/"${DIRECTORY}"
mv "${DIRECTORY}" "${SERVER_DIR}"/
cd "${SERVER_DIR}"
rm latest
ln -s "${DIRECTORY}" latest
EOF
