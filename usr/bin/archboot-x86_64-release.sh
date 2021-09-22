#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
usage () {
	echo "${_BASENAME}:"
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
archboot-create-container.sh archboot-release
# generate tarball in container
systemd-nspawn -D archboot-release archboot-x86_64-iso.sh -t -i=archrelease
# generate iso in container
systemd-nspawn -D archboot-release archboot-x86_64-iso.sh -g -T=archrelease.tar
# move iso out of container
mv archboot-release/*.iso ./
# create boot directory with ramdisks
mkdir boot
mkdir -p boot/licenses/amd-ucode
mkdir -p boot/licenses/intel-ucode
isoinfo -R -i *.iso -x /boot/amd-ucode.img > boot/amd-ucode.img
isoinfo -R -i *.iso -x /boot/intel-ucode.img > boot/intel-ucode.img
isoinfo -R -i *.iso -x /boot/initramfs_x86_64.img > boot/initramfs_archboot_x86_64.img
isoinfo -R -i *.iso -x /boot/vmlinuz_x86_64 > boot/vmlinuz_archboot_x86_64
cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
cp /usr/share/licenses/intel-ucode/* boot/licenses/intel-ucode/
# create torrent file
archboot-mktorrent.sh archboot/$1 *.iso
# create Release.txt with included main archlinux packages
echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM" >>Release.txt
echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>" >>Release.txt
echo "Homepage: https://wiki.archlinux.org/title/Archboot" >>Release.txt
echo "Architecture: x86_64" >>Release.txt
echo "RAM requirement to boot: 1024 MB or greater" >>Release.txt
echo "Kernel:$(systemd-nspawn -D archboot-release pacman -Qi linux | grep Version | cut -d ":" -f2)" >>Release.txt
echo "Pacman:$(systemd-nspawn -D archboot-release pacman -Qi pacman | grep Version | cut -d ":" -f2)" >>Release.txt
echo "Systemd:$(systemd-nspawn -D archboot-release pacman -Qi systemd | grep Version | cut -d ":" -f2)" >>Release.txt
echo "Have fun" >>Release.txt
echo "Tobias Powalowski" >>Release.txt
echo "tpowa@archlinux.org" >>Release.txt
# create sha256sums
sha256sum boot/* >> boot/sha256sum.txt
sha256sum * >> sha256sum.txt
# remove container
rm -r archboot-release
