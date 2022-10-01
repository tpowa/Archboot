#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_AMD_UCODE="boot/amd-ucode.img"
_INTEL_UCODE="boot/intel-ucode.img"
_INITRAMFS="boot/initramfs_${_ARCH}.img"
_INITRAMFS_L0="boot/initramfs_${_ARCH}-0.img"
_INITRAMFS_L1="boot/initramfs_${_ARCH}-1.img"
_INITRAMFS_LATEST="boot/initramfs_${_ARCH}-latest.img"
_INITRAMFS_LOCAL="boot/initramfs_${_ARCH}-local.img"
_INITRAMFS_LOCAL0="boot/initramfs_${_ARCH}-local-0.img"
_INITRAMFS_LOCAL1="boot/initramfs_${_ARCH}-local-1.img"
_KERNEL="boot/vmlinuz_${_ARCH}"
_KERNEL_ARCHBOOT="boot/vmlinuz_archboot_${_ARCH}"
_PRESET_LATEST="${_ARCH}-latest"
_PRESET_LOCAL="${_ARCH}-local"
_W_DIR="$(mktemp -u archboot-release.XXX)"
[[ "${_ARCH}" == "x86_64" ]] && _ISONAME="archboot-archlinux-$(date +%Y.%m.%d-%H.%M)"
[[ "${_ARCH}" == "aarch64" ]] && _ISONAME="archboot-archlinuxarm-$(date +%Y.%m.%d-%H.%M)"
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
    1="${_W_DIR}"
    # create container
    archboot-"${_ARCH}"-create-container.sh "${1}" -cc --install-source="${2}" || exit 1
    _create_archboot_db "${1}"/var/cache/pacman/pkg
    # riscv64 does not support kexec at the moment
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
        # remove not working lvm2 from latest image
        echo "Remove lvm2 from container ${1} ..."
        ${_NSPAWN} pacman -Rdd lvm2 --noconfirm >/dev/null 2>&1
        # generate latest tarball in container
        echo "Generate local ISO ..."
        # generate local iso in container
        ${_NSPAWN} /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_ARCH}" || exit 1
        rm -rf "${1}"/var/cache/pacman/pkg/*
        echo "Generate latest ISO ..."
        # generate latest iso in container
        ${_NSPAWN} /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_ARCH}" || exit 1
        echo "Install lvm2 to container ${1} ..."
        ${_NSPAWN} pacman -Sy lvm2 --noconfirm >/dev/null 2>&1
    fi
    echo "Generate normal ISO ..."
    # generate iso in container
    ${_NSPAWN} /bin/bash -c "umount /tmp;archboot-${_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_ARCH}"  || exit 1
    # create Release.txt with included main archlinux packages
    echo "Generate Release.txt ..."
    (echo "Welcome to ARCHBOOT INSTALLATION / RESCUEBOOT SYSTEM";\
    echo "Creation Tool: 'archboot' Tobias Powalowski <tpowa@archlinux.org>";\
    echo "Homepage: https://bit.ly/archboot";\
    echo "Architecture: ${_ARCH}";\
    echo "RAM requirement to boot: 1300 MB or greater";\
    echo "Archboot:$(${_NSPAWN} pacman -Qi "${_ARCHBOOT}" | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub:$(${_NSPAWN} pacman -Qi grub | grep Version | cut -d ":" -f3 | sed -e "s/\r//g")";\
    echo "Kernel:$(${_NSPAWN} pacman -Qi linux | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Pacman:$(${_NSPAWN} pacman -Qi pacman | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")";\
    echo "Systemd:$(${_NSPAWN} pacman -Qi systemd | grep Version | cut -d ":" -f2 | sed -e "s/\r//g")") >>Release.txt
    # move iso out of container
    mv "${1}"/*.iso ./ > /dev/null 2>&1
    mv "${1}"/*.img ./ > /dev/null 2>&1
    # remove container
    echo "Remove container ${1} ..."
    rm -r "${1}"
}

_create_boot() {
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
                isoinfo -R -i "${i}" -x /"${_INITRAMFS_L0}" 2>/dev/null > "${_INITRAMFS_LOCAL0}"
                isoinfo -R -i "${i}" -x /"${_INITRAMFS_L1}" 2>/dev/null > "${_INITRAMFS_LOCAL1}"
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
}

_create_cksum() {
    # create sha256sums
    echo "Generating sha256sum ..."
    for i in *; do
        [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    done
    for i in boot/*; do
        [[ -f "${i}" ]] && cksum -a sha256 "${i}" >> sha256sum.txt
    done
}
