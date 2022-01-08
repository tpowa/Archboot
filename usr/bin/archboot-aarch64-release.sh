#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_PRESET_LATEST="aarch64-latest"

W_DIR="archboot-release"

usage () {
	echo "CREATE ARCHBOOT RELEASE IMAGE"
	echo "-----------------------------"
	echo "Usage: ${_BASENAME} <directory>"
	echo "This will create an archboot release image in <directory>."
	exit 0
}

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi
echo "Start release creation in $1 ..."
mkdir -p $1
cd $1
# create container
archboot-aarch64-create-container.sh "${W_DIR}" -cc -cp -alf
# generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
echo "Generate ISO ..."
systemd-nspawn -q -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-aarch64-iso.sh -t -i=archrelease"
# generate iso in container
systemd-nspawn -q -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-aarch64-iso.sh -g -T=archrelease.tar"
# remove not working lvm2 from latest image
echo "Remove lvm2 from container ${W_DIR} ..."
systemd-nspawn -D "${W_DIR}" /bin/bash -c "pacman -Rdd lvm2 --noconfirm" >/dev/null 2>&1
# generate latest tarball in container
echo "Generate latest ISO ..."
systemd-nspawn -q -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-aarch64-iso.sh -t -i=latest -p="${_PRESET_LATEST}""
# generate latest iso in container
systemd-nspawn -q -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-aarch64-iso.sh -g -T=latest.tar -p="${_PRESET_LATEST}" -r=$(date +%Y.%m.%d-%H.%M)-latest"
# create Release.txt with included main archlinux packages
echo "Generate Release.txt ..."
echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM" >>Release.txt
echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>" >>Release.txt
echo "Homepage: https://wiki.archlinux.org/title/Archboot" >>Release.txt
echo "Architecture: aarch64" >>Release.txt
echo "RAM requirement to boot: 1152 MB or greater" >>Release.txt
echo "Archboot:$(systemd-nspawn -q -D "${W_DIR}" pacman -Qi archboot-arm | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Kernel:$(systemd-nspawn -q -D "${W_DIR}" pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Pacman:$(systemd-nspawn -q -D "${W_DIR}" pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Systemd:$(systemd-nspawn -q -D "${W_DIR}" pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
# move iso out of container
mv "${W_DIR}"/*.iso ./
# remove container
echo "Remove container ${W_DIR} ..."
rm -r "${W_DIR}"
# create boot directory with ramdisks
echo "Create boot directory ..."
mkdir -p boot/licenses/amd-ucode
for i in *.iso; do
    if [[ ! "$(echo $i | grep latest)" ]]; then
        isoinfo -R -i "${i}" -x /boot/amd-ucode.img > boot/amd-ucode.img 2>&1
        isoinfo -R -i "${i}" -x /boot/initramfs_aarch64.img > boot/initramfs_archboot_aarch64.img 2>&1
        isoinfo -R -i "${i}" -x /boot/vmlinuz_aarch64 > boot/vmlinuz_archboot_aarch64 2>&1
    else
        isoinfo -R -i "${i}" -x /boot/initramfs_aarch64.img > boot/initramfs_archboot_latest_aarch64.img 2>&1
    fi
done
cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
# create torrent files
for i in *.iso; do
    echo "Generating $i torrent ..."
    archboot-mktorrent.sh archboot/"${1}" "${i}" >/dev/null 2>&1
done
# create sha256sums
echo "Generating sha256sum ..."
for i in *; do
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
done
for i in boot/*; do
    [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
done
echo "Finished release creation in $1 ."
