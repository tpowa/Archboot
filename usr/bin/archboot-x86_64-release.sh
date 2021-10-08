#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_PRESET_LATEST="x86_64-latest"

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
mkdir -p $1
cd $1
# create container
archboot-create-container.sh "${W_DIR}" -cc -cp -alf
# generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
systemd-nspawn -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -t -i=archrelease"
# generate iso in container
systemd-nspawn -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -g -T=archrelease.tar"
# remove not working lvm2 from latest image
systemd-nspawn -D "${W_DIR}" /bin/bash -c "pacman -Rdd lvm2 --noconfirm"
# generate latest tarball in container
systemd-nspawn -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -t -i=latest -p="${_PRESET_LATEST}""
# generate latest iso in container
systemd-nspawn -D "${W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -g -T=latest.tar -p="${_PRESET_LATEST}" -r=$(date +%Y.%m.%d-%H.%M)-latest"
# create Release.txt with included main archlinux packages
echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM" >>Release.txt
echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>" >>Release.txt
echo "Homepage: https://wiki.archlinux.org/title/Archboot" >>Release.txt
echo "Architecture: x86_64" >>Release.txt
echo "RAM requirement to boot: 1024 MB or greater" >>Release.txt
echo "Archboot: $(systemd-nspawn -D "${W_DIR}" pacman -Qi archboot | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt
echo "Kernel:$(systemd-nspawn -D "${W_DIR}" pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt
echo "Pacman:$(systemd-nspawn -D "${W_DIR}" pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt
echo "Systemd:$(systemd-nspawn -D "${W_DIR}" pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt
echo "Have fun" >>Release.txt
echo "Tobias Powalowski" >>Release.txt
echo "tpowa@archlinux.org" >>Release.txt
# move iso out of container
mv "${W_DIR}"/*.iso ./
# remove container
rm -r "${W_DIR}"
# create boot directory with ramdisks
mkdir -p boot/licenses/{amd-ucode,intel-ucode}
for i in *.iso; do
    if [[ ! "$(echo $i | grep latest)" ]]; then
        isoinfo -R -i "$i" -x /boot/amd-ucode.img > boot/amd-ucode.img
        isoinfo -R -i "$i" -x /boot/intel-ucode.img > boot/intel-ucode.img
        isoinfo -R -i "$i" -x /boot/initramfs_x86_64.img > boot/initramfs_archboot_x86_64.img
        isoinfo -R -i "$i" -x /boot/vmlinuz_x86_64 > boot/vmlinuz_archboot_x86_64
    else
        isoinfo -R -i "$i" -x /boot/initramfs_x86_64.img > boot/initramfs_archboot_latest_x86_64.img
    fi
done
cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
cp /usr/share/licenses/intel-ucode/* boot/licenses/intel-ucode/
# create torrent file
for i in *.iso; do
    archboot-mktorrent.sh archboot/$1 $i
done
# create sha256sums
cksum -a sha256 boot/* >> boot/sha256sum.txt
cksum -a sha256 * >> sha256sum.txt
