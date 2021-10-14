#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
X86_64="$(mktemp -d X86_64.XXX)"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/x86_64"
_SHIM_VERSION="shim-x64-15.4-5.x86_64.rpm"
_SHIM32_VERSION="shim-ia32-15.4-5.x86_64.rpm"


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
	echo "  -p=PRESET           Which preset should be used."
	echo "                      /etc/archboot/presets locates the presets"
	echo "                      default=x86_64"
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -T=tarball          Use this tarball for image creation."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage


PRESET_DIR="/etc/archboot/presets"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) GENERATE="1" ;;
		-t|--t) TARBALL="1" ;;
                -p=*|--p=*) PRESET="$(echo ${1} | awk -F= '{print $2;}')" ;;
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

#set PRESET
[[ -z "${PRESET}" ]] && PRESET="x86_64"
PRESET=""${PRESET_DIR}"/"${PRESET}""

# from initcpio functions
kver() {
    # this is intentionally very loose. only ensure that we're
    # dealing with some sort of string that starts with something
    # resembling dotted decimal notation. remember that there's no
    # requirement for CONFIG_LOCALVERSION to be set.
    local kver re='^[[:digit:]]+(\.[[:digit:]]+)+'

    # scrape the version out of the kernel image. locate the offset
    # to the version string by reading 2 bytes out of image at at
    # address 0x20E. this leads us to a string of, at most, 128 bytes.
    # read the first word from this string as the kernel version.
    local offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/boot/vmlinuz-linux")
    [[ $offset = +([0-9]) ]] || return 1

    read kver _ < \
        <(dd if="/boot/vmlinuz-linux" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)

    [[ $kver =~ $re ]] || return 1

    KERNEL="$(printf '%s' "$kver")"
}

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && kver
[[ -z "${RELEASENAME}" ]] && RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="archlinux-archboot-${RELEASENAME}-x86_64"

if [[ "${TARBALL}" == "1" ]]; then
	"${TARBALL_HELPER}" -c="${PRESET}" -t="${IMAGENAME}.tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

if ! [[ "${TARBALL_NAME}" == "" ]]; then
        CORE64="$(mktemp -d core64.XXX)"
        tar xf ${TARBALL_NAME} -C "${CORE64}" || exit 1
    else
        echo "Please enter a tarball name with parameter -T=tarball"
        exit 1
fi

mkdir -p "${X86_64}/EFI/BOOT"

_prepare_kernel_initramfs_files() {

	mkdir -p "${X86_64}/boot"
        mv "${CORE64}"/*/boot/vmlinuz "${X86_64}/boot/vmlinuz_x86_64"
        mv "${CORE64}"/*/boot/initrd.img "${X86_64}/boot/initramfs_x86_64.img"
	mv "${CORE64}"/*/boot/{memtest,intel-ucode.img,amd-ucode.img} "${X86_64}/boot/"
        
}

_prepare_keytool_uefi () {
    cp -f "/usr/share/efitools/efi/KeyTool.efi" "${X86_64}/EFI/BOOT/KeyTool.efi"
}

_prepare_fedora_shim_bootloaders () {
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    SHIM=$(mktemp -d shim.XXXX)
    curl --create-dirs -L -O --output-dir "${SHIM}" "${_SHIM_URL}/${_SHIM_VERSION}"
    bsdtar -C "${SHIM}" -xf "${SHIM}"/"${_SHIM_VERSION}"
    cp "${SHIM}/boot/efi/EFI/fedora/mmx64.efi" "${X86_64}/EFI/BOOT/mmx64.efi"
    cp "${SHIM}/boot/efi/EFI/fedora/shimx64.efi" "${X86_64}/EFI/BOOT/BOOTX64.efi"
    # add shim ia32 signed files from fedora
    SHIM32=$(mktemp -d shim32.XXXX)
    curl --create-dirs -L -O --output-dir "${SHIM32}" "${_SHIM_URL}/${_SHIM32_VERSION}"
    bsdtar -C "${SHIM32}" -xf "${SHIM32}/${_SHIM32_VERSION}"
    cp "${SHIM32}/boot/efi/EFI/fedora/mmia32.efi" "${X86_64}/EFI/BOOT/mmia32.efi"
    cp "${SHIM32}/boot/efi/EFI/fedora/shimia32.efi" "${X86_64}/EFI/BOOT/BOOTIA32.efi"
    ### adding this causes boot loop in ovmf and only tries create a boot entry
    #cp "${SHIM}/boot/efi/EFI/BOOT/fbx64.efi" "${X86_64}/EFI/BOOT/fbx64.efi"
}

_prepare_secure_boot() {
    # add mkkeys.sh
    MKKEYS=$(mktemp -d mkkeys.XXXX)
    curl -L -O --output-dir ${MKKEYS} https://www.rodsbooks.com/efi-bootloaders/mkkeys.sh 
    chmod 755 ${MKKEYS}/mkkeys.sh
    cd ${MKKEYS}
    ./mkkeys.sh
    curl -L -O --output-dir ${MKKEYS} https://www.microsoft.com/pkiops/certs/MicWinProPCA2011_2011-10-19.crt
    curl -L -O --output-dir ${MKKEYS} https://www.microsoft.com/pkiops/certs/MicCorUEFCA2011_2011-06-27.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_Win_db.esl MicWinProPCA2011_2011-10-19.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_UEFI_db.esl MicCorUEFCA2011_2011-06-27.crt
    cat MS_Win_db.esl MS_UEFI_db.esl > MS_db.esl
    sign-efi-sig-list -a -g 77fa9abd-0359-4d32-bd60-28f4e78f784b -k KEK.key -c KEK.crt db MS_db.esl add_MS_db.auth
    cd ..
    cp -v ${MKKEYS}/* "${X86_64}"/EFI/
    sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/boot/vmlinuz-linux ${X86_64}/boot/vmlinuz_x86_64
    #sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/boot/vmlinuz-linux ${X86_64}/EFI/grubx64.efi
    # move in shim
    #cp -v /usr/share/shim/BOOTX64.CSV ${X86_64}/EFI/BOOT
    #cp -v /usr/share/shim/fbx64.efi ${X86_64}/EFI/BOOT
    #cp -v /usr/share/shim/mmx64.efi ${X86_64}/EFI/BOOT
    #cp -v /usr/share/shim/shimx64.efi ${X86_64}/EFI/BOOT/BOOTX64.efi
    #cp -v /usr/share/shim/shimx64.efi ${X86_64}/EFI/BOOT/shimx64.efi
    #sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/EFI/BOOT/BOOTX64.efi ${X86_64}/EFI/BOOT/BOOTX64.efi
    #sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/EFI/BOOT/grubx64.efi ${X86_64}/EFI/BOOT/grubx64.efi
    #sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/EFI/BOOT/shimx64.efi ${X86_64}/EFI/BOOT/shimx64.efi
    #sbsign --key ${MKKEYS}/DB.key --cert ${MKKEYS}/DB.crt --output ${X86_64}/EFI/BOOT/BOOTIA32.EFI ${X86_64}/EFI/BOOT/BOOTIA32.EFI
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
	mcopy -i "${VFAT_IMAGE}" -s "${X86_64}"/{EFI,boot} ::/
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${X86_64}/EFI/tools/"
	
	## Install Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
	cp /usr/share/edk2-shell/x64/Shell.efi "${X86_64}/EFI/tools/shellx64_v2.efi" 
	
	## Install Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
	cp /usr/share/edk2-shell/x64/Shell_Full.efi "${X86_64}/EFI/tools/shellx64_v1.efi" 
	
	## Install Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
	cp /usr/share/edk2-shell/ia32/Shell.efi "${X86_64}/EFI/tools/shellia32_v2.efi"
	
	## InstallTianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
	cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${X86_64}/EFI/tools/shellia32_v1.efi" 
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_X64_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"	
	cp "/usr/share/archboot/grub//grubx64.efi" "${X86_64}/EFI/BOOT/grubx64.efi" 
	cat << GRUBEOF > "${X86_64}/EFI/BOOT/grubx64.cfg"
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
	cp "/usr/share/archboot/grub//grubia32.efi" "${X86_64}/EFI/BOOT/grubia32.efi" 
	
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

_prepare_fedora_shim_bootloaders

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_keytool_uefi

_prepare_uefi_X64_GRUB_USB_files

_prepare_uefi_IA32_GRUB_USB_files

#_prepare_secure_boot

_prepare_uefi_image

# place syslinux files
mkdir -p "${X86_64}/boot/syslinux"
mv "${CORE64}"/*/boot/syslinux/* "${X86_64}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${X86_64}/boot/syslinux/boot.msg"

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
        -output "${IMAGENAME}.iso" "${X86_64}/" &> "${IMAGENAME}.log"

## create sha256sums.txt
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
rm -rf "${CORE64}"
rm -rf "${X86_64}"
