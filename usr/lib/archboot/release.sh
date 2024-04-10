#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_AMD_UCODE="boot/amd-ucode.img"
_INTEL_UCODE="boot/intel-ucode.img"
_INITRD="boot/initrd-${_ARCH}.img"
_INITRD_LATEST="boot/initrd-latest-${_ARCH}.img"
_INITRD_LOCAL="boot/initrd-local-${_ARCH}.img"
if [[ "${_ARCH}" == "aarch64" ]]; then
    _KERNEL_ARCHBOOT="boot/Image-${_ARCH}.gz"
else
    _KERNEL_ARCHBOOT="boot/vmlinuz-${_ARCH}"
fi
_CONFIG_LATEST="${_ARCH}-latest.conf"
_CONFIG_LOCAL="${_ARCH}-local.conf"
_W_DIR="$(mktemp -u archboot-release.XXX)"

_usage () {
    echo "CREATE ARCHBOOT RELEASE IMAGE"
    echo "-----------------------------"
    echo "This will create an archboot release image in <directory>."
    echo "You can specify a certain <server> with an archboot repository."
    echo ""
    echo "usage: ${_BASENAME} <directory> <server>"
    exit 0
}

_create_initrd_dir() {
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-cpio.sh \
        -k "${_KERNEL}" -c "/etc/archboot/${1}" -d /tmp/initrd" || exit 1
}

_compress_initrd() {
    echo "Creating zstd compressed image: ${1}"
    pushd "${_W_DIR}/tmp/initrd" >"${_NO_LOG}" || return
    # Reproducibility: set all timestamps to 0
    find . -mindepth 1 -execdir touch -hcd "@0" "{}" +
    # use zstd only it has best compression and decompression
    find . -mindepth 1 -printf '%P\0' | sort -z |
        LANG=C bsdtar --null -cnf - -T - |
        LANG=C bsdtar --null -cf - --format=newc @- |
        zstd -T0 -19 > "../../${1}" || exit 1
    popd >"${_NO_LOG}" || return
    echo "Build complete."
}

_create_iso() {
    mkdir -p "${1}"
    cd "${1}" || exit 1
    # create container
    archboot-"${_ARCH}"-create-container.sh "${_W_DIR}" -cc --install-source="${2}" || exit 1
    _create_archboot_db "${_W_DIR}${_CACHEDIR}"
    #shellcheck disable=SC1090
    . "${_W_DIR}/etc/archboot/${_ARCH}.conf"
    #shellcheck disable=SC2116,SC2046,SC2027,2086
    _KERNEL_VERSION="$(${_NSPAWN} "${_W_DIR}" /bin/bash -c "_KERNEL="$(echo ${_KERNEL})";. /usr/lib/archboot/common.sh; _kver ${_KERNEL}")"
    _ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)-${_KERNEL_VERSION}"
    if ! [[ "${_RUNNING_ARCH}" == "${_ARCH}" ]]; then
        ### to speedup build for riscv64 and aarch64 on x86_64, run compressor on host system
        echo "Generating initramdisks..."
        # init ramdisk
        _create_initrd_dir "${_ARCH}-init.conf"
        . "/etc/archboot/${_ARCH}-init.conf"
        _compress_initrd "init-${_ARCH}.img"
        if ! [[ "${_ARCH}" == "riscv64" ]]; then
            # local ramdisk
            echo "Generating local initramfs..."
            _create_initrd_dir "${_CONFIG_LOCAL}"
            . "/etc/archboot/${_CONFIG_LOCAL}"
            _compress_initrd "initrd-local-${_ARCH}.img"
            # latest ramdisk
            echo "Generating latest initramfs..."
            _create_initrd_dir "${_CONFIG_LATEST}"
            . "/etc/archboot/${_CONFIG_LATEST}"
            _compress_initrd "initrd-latest-${_ARCH}.img"
        fi
        # normal ramdisk
        echo "Generating normal initramfs..."
        _create_initrd_dir "${_ARCH}.conf"
        . "/etc/archboot/${_ARCH}.conf"
        _compress_initrd "initrd-${_ARCH}.img"
    fi
    # riscv64 does not support kexec at the moment
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp container tmpfs, else weird things could happen
        # removing not working lvm2 from latest and local image first
        echo "Generating local ISO..."
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g -s \
            -c=${_CONFIG_LOCAL} -i=${_ISONAME}-local-${_ARCH}" || exit 1
        echo "Generating latest ISO..."
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g \
            -c=${_CONFIG_LATEST} -i=${_ISONAME}-latest-${_ARCH}" || exit 1
    fi
    echo "Generating normal ISO..."
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_ARCH}-iso.sh -g -s \
        -i=${_ISONAME}-${_ARCH}" || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>"${_NO_LOG}"
    mv "${_W_DIR}"/*.img ./ &>"${_NO_LOG}"
    # create boot directory with ramdisks
    echo "Creating boot directory..."
    mkdir -p boot/
    mv init-* boot/
    if [[ "${_ARCH}" == "riscv64" ]]; then
        for i in *.img; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_KERNEL_ARCHBOOT}" ./"${_KERNEL_ARCHBOOT}"
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD}"
            elif echo "${i}" | grep -q latest; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD_LATEST}"
            elif echo "${i}" | grep -q local; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD_LOCAL}"
            fi
        done
    else
        for i in *.iso; do
            if  echo "${i}" | grep -v local | grep -vq latest; then
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_AMD_UCODE}" ./"${_AMD_UCODE}"
                [[ "${_ARCH}" == "aarch64" ]] || mcopy -m -i efi.img ::/"${_INTEL_UCODE}" ./"${_INTEL_UCODE}"
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD}"
                mcopy -m -i efi.img ::/"${_KERNEL_ARCHBOOT}" ./"${_KERNEL_ARCHBOOT}"
            elif echo "${i}" | grep -q latest; then
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD_LATEST}"
            elif echo "${i}" | grep -q local; then
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD_LOCAL}"
            fi
            rm efi.img
        done
        echo "Generating Unified Kernel Images..."
        # create unified kernel image UKI, code adapted from wiki
        # https://wiki.archlinux.org/title/Unified_kernel_image
        _SPLASH="/usr/share/archboot/uki/archboot-background.bmp"
        _OSREL="/usr/share/archboot/base/etc/os-release"
        # add AMD ucode license
        mkdir -p licenses/amd-ucode
        cp /usr/share/licenses/amd-ucode/* licenses/amd-ucode/
        _CMDLINE="boot/cmdline.txt"
        if [[ "${_ARCH}" == "x86_64" ]]; then
            # add INTEL ucode license
            mkdir -p licenses/intel-ucode
            cp /usr/share/licenses/intel-ucode/* licenses/intel-ucode/
            _EFISTUB="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"
            echo "console=ttyS0,115200 console=tty0 audit=0 systemd.show_status=auto" > ${_CMDLINE}
        fi
        if [[ "${_ARCH}" == "aarch64" ]]; then
            echo "nr_cpus=1 console=ttyAMA0,115200 console=tty0 loglevel=4 audit=0 systemd.show_status=auto" > ${_CMDLINE}
            _EFISTUB="/usr/lib/systemd/boot/efi/linuxaa64.efi.stub"
            _INTEL_UCODE=""
            # replace aarch64 Image.gz with Image kernel for UKI, compressed image is not working at the moment
            cp "${_W_DIR}/boot/Image" "boot/Image-${_ARCH}"
            _KERNEL_ARCHBOOT="boot/Image-${_ARCH}"
        fi
        [[ -n "${_INTEL_UCODE}" ]] && _INTEL_UCODE="--initrd=${_INTEL_UCODE}"
        [[ -n "${_AMD_UCODE}" ]] && _AMD_UCODE="--initrd=${_AMD_UCODE}"
        rm -r "${_W_DIR:?}"/boot
        mv boot "${_W_DIR}"
        for initrd in ${_INITRD} ${_INITRD_LATEST} ${_INITRD_LOCAL}; do
            [[ "${initrd}" == "${_INITRD}" ]] && _UKI="boot/archboot-${_ARCH}.efi"
            [[ "${initrd}" == "${_INITRD_LATEST}" ]] && _UKI="boot/archboot-latest-${_ARCH}.efi"
            [[ "${initrd}" == "${_INITRD_LOCAL}" ]] && _UKI="boot/archboot-local-${_ARCH}.efi"
            #shellcheck disable=SC2086
            ${_NSPAWN} "${_W_DIR}" /usr/lib/systemd/ukify build --linux=${_KERNEL_ARCHBOOT} \
                ${_INTEL_UCODE} ${_AMD_UCODE} --initrd=${initrd} --cmdline=@${_CMDLINE} \
                --os-release=@${_OSREL} --splash=${_SPLASH} --output=${_UKI} &>"${_NO_LOG}" || exit 1
        done
        # fix permission and timestamp
        mv "${_W_DIR}"/boot ./
        rm "${_CMDLINE}"
        chmod 644 boot/*.efi
    fi
    touch boot/*
    echo "Generating Release.txt..."
    ${_NSPAWN} "${_W_DIR}" pacman -Sy "${_W_DIR}" &>"${_NO_LOG}"
    (echo "ARCHBOOT - ARCH LINUX INSTALLATION / RESCUE SYSTEM"
    echo "archboot.com | (c) 2006 - $(date +%Y)"
    echo "Tobias Powalowski <tpowa@archlinux.org>"
    echo ""
    echo "Requirement: ${_ARCH} with 800M RAM and higher"
    echo "Archboot:$(${_NSPAWN} "${_W_DIR}" pacman -Qi "${_ARCHBOOT}" | grep Version |\
         cut -d ":" -f2 | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g")"
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub: $(${_NSPAWN} "${_W_DIR}" pacman -Qi grub |\
                                     grep Version | cut -d ":" -f3 | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g")"
    echo "Linux:$(${_NSPAWN} "${_W_DIR}" pacman -Qi linux | grep Version |\
         cut -d ":" -f2 | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g")"
    echo "Pacman:$(${_NSPAWN} "${_W_DIR}" pacman -Qi pacman | grep Version |\
         cut -d ":" -f2 | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g")"
    echo "Systemd:$(${_NSPAWN} "${_W_DIR}" pacman -Qi systemd | grep Version |\
         cut -d ":" -f2 | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g")"
    echo ""
    echo "---Complete Package List---"
    ${_NSPAWN} "${_W_DIR}" pacman -Q | sed -e "s/\r//g" -e "s/\x1b\[[0-9;]*m//g" \
         -e "s/\x1b\[.*[0-9][h;l]//g") >>Release.txt
    echo "Removing container ${_W_DIR}..."
    rm -r "${_W_DIR}"
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        echo "Creating iso/ directory..."
        mkdir iso
        mv *.iso iso/
        echo "Creating uki/ directory..."
        mkdir uki
        mv boot/*.efi uki/
    else
        echo "Creating img/ directory..."
        mkdir img
        mv *.img img/
    fi
    echo "Generating b2sum..."
    for i in *; do
        if [[ -f "${i}" ]]; then
            cksum -a blake2b "${i}" >> b2sum.txt
        fi
    done
    for i in boot/*; do
        if [[ -f "${i}" ]]; then
            cksum -a blake2b "${i}" >> b2sum.txt
        fi
    done
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        for i in iso/* uki/*; do
            if [[ -f "${i}" ]]; then
                cksum -a blake2b "${i}" >> b2sum.txt
            fi
        done
    else
        for i in img/*; do
            if [[ -f "${i}" ]]; then
                cksum -a blake2b "${i}" >> b2sum.txt
            fi
        done
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
