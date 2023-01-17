#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_AMD_UCODE="boot/amd-ucode.img"
_INTEL_UCODE="boot/intel-ucode.img"
_INITRAMFS="boot/initramfs_${_ARCH}.img"
_INITRAMFS_LATEST="boot/initramfs_${_ARCH}-latest.img"
_INITRAMFS_LOCAL="boot/initramfs_${_ARCH}-local.img"
_KERNEL="boot/vmlinuz_${_ARCH}"
_KERNEL_ARCHBOOT="boot/vmlinuz_archboot_${_ARCH}"
_PRESET_LATEST="${_ARCH}-latest"
_PRESET_LOCAL="${_ARCH}-local"
_W_DIR="$(mktemp -u archboot-release.XXX)"
if [[ "${_ARCH}" == "x86_64" ]]; then
    _ISONAME="archboot-archlinux-$(date +%Y.%m.%d-%H.%M)"
    _EFISTUB="x64"
    _CMDLINE="rootfstype=ramfs console=ttyS0,115200 console=tty0 audit=0"
fi
if [[ "${_ARCH}" == "aarch64" ]]; then
    _ISONAME="archboot-archlinuxarm-$(date +%Y.%m.%d-%H.%M)"
    _EFISTUB="aa64"
    _CMDLINE="rootfstype=ramfs nr_cpus=1 console=ttyAMA0,115200 console=tty0 loglevel=4 audit=0"
fi
[[ "${_ARCH}" == "riscv64" ]] && _ISONAME="archboot-archlinuxriscv-$(date +%Y.%m.%d-%H.%M)"

_usage () {
    echo "CREATE ARCHBOOT RELEASE IMAGE"
    echo "-----------------------------"
    echo "Usage: ${_BASENAME} <directory> <server>"
    echo "This will create an archboot release image in <directory>."
    echo "You can specify a certain <server> with an archboot repository."
    exit 0
}

_create_iso() {
    mkdir -p "${1}"
    cd "${1}" || exit 1
    # create container
    archboot-"${_ARCH}"-create-container.sh "${_W_DIR}" -cc --install-source="${2}" || exit 1
    _create_archboot_db "${_W_DIR}"/var/cache/pacman/pkg
    # riscv64 does not support kexec at the moment
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
        # remove not working lvm2 from latest image
        echo "Remove lvm2 from container ${_W_DIR} ..."
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm >/dev/null 2>&1
        # generate latest tarball in container
        echo "Generate local ISO ..."
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_ARCH}" || exit 1
        rm -rf "${_W_DIR}"/var/cache/pacman/pkg/*
        echo "Generate latest ISO ..."
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_ARCH}" || exit 1
        echo "Install lvm2 to container ${_W_DIR} ..."
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm >/dev/null 2>&1
    fi
    echo "Generate normal ISO ..."
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_ARCH}"  || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ > /dev/null 2>&1
    mv "${_W_DIR}"/*.img ./ > /dev/null 2>&1
    # create boot directory with ramdisks
    echo "Create boot directory ..."
    if [[ "${_ARCH}" == "riscv64" ]]; then
        mkdir -p boot/
        for i in *.img; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_KERNEL}" ./"${_KERNEL_ARCHBOOT}"
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS}"
            elif echo "${i}" | grep -q latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS_LATEST}"
            elif echo "${i}" | grep -q local; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRAMFS}" ./"${_INITRAMFS_LOCAL}"
            fi
        done
    else
        mkdir -p boot/licenses/amd-ucode
        [[ "${_ARCH}" == "aarch64" ]] || mkdir -p boot/licenses/intel-ucode
        for i in *.iso; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                isoinfo -R -i "${i}" -x /"${_AMD_UCODE}" 2>/dev/null > "${_AMD_UCODE}"
                [[ "${_ARCH}" == "aarch64" ]] || isoinfo -R -i "${i}" -x /"${_INTEL_UCODE}" 2>/dev/null > "${_INTEL_UCODE}"
                isoinfo -R -i "${i}" -x /"${_INITRAMFS}" 2>/dev/null > "${_INITRAMFS}"
                isoinfo -R -i "${i}" -x /"${_KERNEL}" 2>/dev/null > "${_KERNEL_ARCHBOOT}"
            elif echo "${i}" | grep -q latest; then
                isoinfo -R -i "${i}" -x /"${_INITRAMFS}" 2>/dev/null > "${_INITRAMFS_LATEST}"
            elif echo "${i}" | grep -q local; then
                isoinfo -R -i "${i}" -x /"${_INITRAMFS}" 2>/dev/null > "${_INITRAMFS_LOCAL}"
            fi
        done
        if [[ -d /usr/share/licenses/amd-ucode ]]; then
            cp /usr/share/licenses/amd-ucode/* boot/licenses/amd-ucode/
        fi
        if ! [[ "${_ARCH}" == "aarch64" ]]; then
            if [[ -d /usr/share/licenses/intel-ucode ]]; then
                cp /usr/share/licenses/intel-ucode/* boot/licenses/intel-ucode/
            fi
        fi
    fi
    echo "Generate Unified Kernel Images ..."
    # create unified kernel image UKI
    if [[ "${_ARCH}" == "x86_64" ]]; then
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_INTEL_UCODE}" "${_AMD_UCODE}" "${_INITRAMFS}") \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}.efi""
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_INTEL_UCODE}" "${_AMD_UCODE}" "${_INITRAMFS_LATEST}") \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}-latest.efi""
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_INTEL_UCODE}" "${_AMD_UCODE}" "${_INITRAMFS_LOCAL}") \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}-local.efi""
            chmod 644 boot/*.efi
    elif [[ "${_ARCH}" == "aarch64" ]]; then
        ${_NSPAWN} "${_W_DIR}"  /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_AMD_UCODE}" boot/initramfs_"${_ARCH}".img) \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}.efi""
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_AMD_UCODE}" "${_INITRAMFS_LATEST}") \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}-latest.efi""
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "objcopy -p --add-section .osrel="/usr/share/archboot/base/etc/os-release" --change-section-vma .osrel=0x20000 \
            --add-section .cmdline=<(echo "${_CMDLINE}" | tr -s '\n' ' '; printf '\n\0') --change-section-vma .cmdline=0x30000 \
            --add-section .linux="${_KERNEL_ARCHBOOT}" --change-section-vma .linux=0x2000000 \
            --add-section .initrd=<(cat "${_AMD_UCODE}" "${_INITRAMFS_LOCAL}") \
            --change-section-vma .initrd=0x3000000 "linux${_EFISTUB}.efi.stub" \
            --add-section .splash="/usr/share/archboot/uki/archboot-background.bmp" \
            --change-section-vma .splash=0x40000 "boot/archboot-${_EFISTUB}-local.efi""
            chmod 644 boot/*.efi
    fi
    # create Release.txt with included main archlinux packages
    echo "Generate Release.txt ..."
    (echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM";\
    echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>";\
    echo "Homepage: https://bit.ly/archboot";\
    echo "Architecture: ${_ARCH}";\
    echo "RAM requirement to boot: 1300 MB or greater";\
    echo "Archboot:$(${_NSPAWN} "${_W_DIR}" pacman -Qi "${_ARCHBOOT}" | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub:$(${_NSPAWN} "${_W_DIR}" pacman -Qi grub | grep Version | cut -d ":" -f3 | sed -e "s/\r//g")";\
    echo "Kernel:$(${_NSPAWN} "${_W_DIR}" pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Pacman:$(${_NSPAWN} "${_W_DIR}" pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Systemd:$(${_NSPAWN} "${_W_DIR}" pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")") >>Release.txt
    # remove container
    echo "Remove container ${_W_DIR} ..."
    rm -r "${_W_DIR}"
    # create sha256sums
    echo "Generating sha256sum ..."
    for i in *; do
        [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    done
    for i in boot/*; do
        [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    done
}
