#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_PRESET_LATEST="x86_64-latest"
_W_DIR="$(mktemp -u archboot-release.XXX)"

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
### check for x86_64
if ! [[ "$(uname -m)" == "x86_64" ]]; then
    echo "ERROR: Pleae run on x86_64 hardware."
    exit 1
fi
echo "Start release creation in $1 ..."
mkdir -p "$1"
cd "$1" || exit 1
# create container
archboot-x86_64-create-container.sh "${_W_DIR}" -cc -cp || exit 1
# generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
echo "Generate ISO ..."
# generate iso in container
systemd-nspawn -q -D "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -g"
# remove not working lvm2 from latest image
echo "Remove lvm2 and openssh from container ${_W_DIR} ..."
systemd-nspawn -D "${_W_DIR}" /bin/bash -c "pacman -Rdd lvm2 openssh --noconfirm" >/dev/null 2>&1
# generate latest tarball in container
echo "Generate latest ISO ..."
# generate latest iso in container
systemd-nspawn -q -D "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-x86_64-iso.sh -g -p=${_PRESET_LATEST} -r=$(date +%Y.%m.%d-%H.%M)-latest"
# create Release.txt with included main archlinux packages
echo "Generate Release.txt ..."
echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM" >>Release.txt
echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>" >>Release.txt
echo "Homepage: https://wiki.archlinux.org/title/Archboot" >>Release.txt
echo "Architecture: x86_64" >>Release.txt
echo "RAM requirement to boot: 1152 MB or greater" >>Release.txt
echo "Archboot:$(systemd-nspawn -q -D "${_W_DIR}" pacman -Qi archboot | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Kernel:$(systemd-nspawn -q -D "${_W_DIR}" pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Pacman:$(systemd-nspawn -q -D "${_W_DIR}" pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
echo "Systemd:$(systemd-nspawn -q -D "${_W_DIR}" pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")" >>Release.txt 
# move iso out of container
mv "${_W_DIR}"/*.iso ./
# remove container
echo "Remove container ${_W_DIR} ..."
rm -r "${_W_DIR}"
# create boot directory with ramdisks
echo "Create boot directory ..."
mkdir -p boot/licenses/{amd-ucode,intel-ucode}
for i in *.iso; do
    if ! grep -q latest "${i}"; then
        isoinfo -R -i "${i}" -x /boot/amd-ucode.img > boot/amd-ucode.img 2>&1
        isoinfo -R -i "${i}" -x /boot/intel-ucode.img > boot/intel-ucode.img 2>&1
        isoinfo -R -i "${i}" -x /boot/initramfs_x86_64.img > boot/initramfs_archboot_x86_64.img 2>&1
        isoinfo -R -i "${i}" -x /boot/vmlinuz_x86_64 > boot/vmlinuz_archboot_x86_64 2>&1
    else
        isoinfo -R -i "${i}" -x /boot/initramfs_x86_64.img > boot/initramfs_archboot_latest_x86_64.img 2>&1
    fi
done
cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
cp /usr/share/licenses/intel-ucode/* boot/licenses/intel-ucode/
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
