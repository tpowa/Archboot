#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

[[ -z "${WD}" ]] && WD="${PWD}/"

_BASENAME="$(basename "${0}")"

_CARCH="x86_64"
_UEFI_ARCH="X64"
_SPEC_UEFI_ARCH="x64"

usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE X86_64 USB/CD IMAGES"
	echo "-----------------------------"
	echo "Run in archboot x86_64 chroot first ..."
	echo "archboot-x86_64-iso.sh -t"
	echo ""
	echo "PARAMETERS:"
	echo "  -t                  Start generation of tarball."
	echo "  -g                  Start generation of image."
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -T=tarball          Use this tarball for image creation."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage


PRESET="/etc/archboot/presets/x86_64"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) GENERATE="1" ;;
		-t|--t) TARBALL="1" ;;
		-i=*|--i=*) IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) RELEASENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) KERNEL="$(echo ${1} | awk -F= '{print $2;}')" ;;
                -T=*|--T=*) TARBALL_NAME="$(echo ${1} | awk -F= '{print $2;}')" ;;	
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

# set defaults, if nothing given
[[ -z "${RELEASENAME}" ]] && RELEASENAME="$(date +%Y%m%d-%H%M)"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="archlinux-${RELEASENAME}-archboot"

if [[ "${TARBALL}" == "1" ]]; then
	"${TARBALL_HELPER}" -c="${PRESET}" -t="${IMAGENAME}.tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

if ! [[ "${TARBALL_NAME}" == "" ]]; then
        CORE64="$(mktemp -d ${WD}/core64.XXX)"
        tar xvf ${TARBALL_NAME} -C "${CORE64}" || exit 1
    else
        echo "Please enter a tarball name with parameter -T=tarball"
        exit 1
fi

X86_64="$(mktemp -d ${WD}/X86_64.XXX)"

_prepare_kernel_initramfs_files() {
	
        mv "${CORE64}"/*/boot/vmlinuz "${X86_64}/boot/vmlinuz_x86_64"
        mv "${CORE64}"/*/boot/initrd.img "${X86_64}/boot/initramfs_x86_64.img"
	mv "${CORE64}"/*/boot/{memtest,intel-ucode.img,amd-ucode.img} "${X86_64}/boot/"
        
}

_prepare_other_files() {
	
	# move in doc
	mkdir -p "${X86_64}/arch/"
	mv "${CORE64}"/*/arch/archboot.txt "${X86_64}/arch/"
	
}

_prepare_uefi_image() {
        
        ## get size of boot x86_64 files
	BOOTSIZE=$(du -bc ${X86_64} | grep total | cut -f1)
	IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors
	
	mkdir -p "${X86_64}"/CDEFI/
	
	## Create cdefiboot.img
	dd if=/dev/zero of="${X86_64}"/CDEFI/cdefiboot.img bs="${IMGSZ}" count=1024
	VFAT_IMAGE="${X86_64}/CDEFI/cdefiboot.img"
	mkfs.vfat "${VFAT_IMAGE}"
	
	## Copy all files to UEFI vfat image
	mcopy -i "${VFAT_IMAGE}" -s "${X86_64}"/{EFI,loader,boot} ::/
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${X86_64}/EFI/tools/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellx64_v2.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X64/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellx64_v1.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellia32_v2.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/Ia32/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellia32_v1.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/Ia32/Shell_Full.efi"
	
}

_prepare_uefi_systemd-boot_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	cp -f "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${X86_64}/EFI/BOOT/loader.efi"
	
	mkdir -p "${X86_64}/loader/entries"
	
	cat << GUMEOF > "${X86_64}/loader/loader.conf"
timeout  4
default  default-*
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/archboot-x86_64-efistub.conf"
title           Arch Linux x86_64 Archboot EFISTUB
linux           /boot/vmlinuz_x86_64
initrd          /boot/intel-ucode.img
initrd          /boot/amd-ucode.img
initrd          /boot/initramfs_x86_64.img
options         cgroup_disable=memory add_efi_memmap _X64_UEFI=1 rootfstype=ramfs
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/uefi-shell-x64-v2.conf"
title           UEFI Shell X64 v2
efi             /EFI/tools/shellx64_v2.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/uefi-shell-x64-v1.conf"
title           UEFI Shell X64 v1
efi             /EFI/tools/shellx64_v1.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/grub-x64-systemd-boot.conf"
title           GRUB X64 - if EFISTUB boot fails
efi             /EFI/grub/grubx64.efi
architecture    x64
GUMEOF
	
	mv "${X86_64}/loader/entries/archboot-x86_64-efistub.conf" "${X86_64}/loader/entries/default-x64.conf"
	
}

_prepare_uefi_X64_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/grub"
	
	echo 'configfile ${cmdpath}/grubx64.cfg' > ${X86_64}/grubx64.cfg
	grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/grub/grubx64.efi" "boot/grub/grub.cfg=${X86_64}/grubx64.cfg" -v
	
	cat << GRUBEOF > "${X86_64}/EFI/grub/grubx64.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod efi_gop
insmod efi_uga
insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux x86_64 Archboot Non-EFISTUB"
set timeout="2"

menuentry "Arch Linux x86_64 Archboot Non-EFISTUB" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _X64_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "UEFI Shell X64 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v2.efi
    chainloader /EFI/tools/shellx64_v2.efi
}

menuentry "UEFI Shell X64 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v1.efi
    chainloader /EFI/tools/shellx64_v1.efi
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        
	rm ${X86_64}/grubx64.cfg
	
}

_prepare_uefi_IA32_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	
	echo 'configfile ${cmdpath}/bootia32.cfg' > ${X86_64}/bootia32.cfg
	grub-mkstandalone -d /usr/lib/grub/i386-efi/ -O i386-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/BOOT/BOOTIA32.EFI" "boot/grub/grub.cfg=${X86_64}/bootia32.cfg" -v
	
	cat << GRUBEOF > "${X86_64}/EFI/BOOT/bootia32.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod efi_gop
insmod efi_uga
insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux x86_64 Archboot - EFI MIXED MODE"
set timeout="2"

menuentry "Arch Linux x86_64 Archboot - EFI MIXED MODE" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _IA32_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "UEFI Shell IA32 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v2.efi
    chainloader /EFI/tools/shellia32_v2.efi
}

menuentry "UEFI Shell IA32 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v1.efi
    chainloader /EFI/tools/shellia32_v1.efi
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        
        rm ${X86_64}/bootia32.cfg
        
}

_prepare_other_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_uefi_systemd-boot_USB_files

_prepare_uefi_X64_GRUB_USB_files

_prepare_uefi_IA32_GRUB_USB_files

_prepare_uefi_image

# place syslinux files
mkdir -p "${X86_64}/boot/syslinux"
mv "${CORE64}"/*/boot/syslinux/* "${X86_64}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${X86_64}/boot/syslinux/boot.msg"

cd "${WD}/"

## Generate the BIOS+ISOHYBRID+UEFI CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating X86_64 hybrid ISO ..."
xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "ARCHBOOT" \
        -preparer "prepared by ${_BASENAME}" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
        -eltorito-alt-boot -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat -no-emul-boot \
        -output "${IMAGENAME}.iso" "${X86_64}/" &> "${WD}/${IMAGENAME}.log"

## create sha256sums.txt
cd "${WD}/"
rm -f "${WD}/sha256sums.txt" || true
sha256sum *.iso > "${WD}/sha256sums.txt"

# cleanup
rm -rf "${CORE64}"
rm -rf "${X86_64}"
