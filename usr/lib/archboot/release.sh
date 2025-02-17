#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_INITRD="boot/initrd-${_ARCH}.img"
_INITRD_LATEST="boot/initrd-latest-${_ARCH}.img"
_INITRD_LOCAL="boot/initrd-local-${_ARCH}.img"
_CONFIG_LATEST="${_ARCH}-latest.conf"
_CONFIG_LOCAL="${_ARCH}-local.conf"
_W_DIR="$(mktemp -u archboot-release.XXX)"

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create Release Images\e[m"
    echo -e "\e[1m--------------------------------\e[m"
    echo "This will create an Archboot release image in <directory>."
    echo "Optional: You can specify a certain <server> with an Archboot repository."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <directory> <server>\e[m"
    exit 0
}

_create_initrd_dir() {
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-cpio.sh \
        -c /etc/archboot/${1} -firmware -d /tmp/initrd" || exit 1
}

_create_fw_cpio() {
    [[ -d "${_W_DIR}/firmware" ]] || mkdir -p "${_W_DIR}/firmware"
    for i in "${_W_DIR}"/tmp/archboot-firmware/*; do
        echo "Preparing $(basename ${i}).img firmware..."
        _create_cpio "${i}" "../../../firmware/$(basename "${i}").img" &>"${_NO_LOG}"
    done
}

_create_iso() {
    mkdir -p "${1}"
    cd "${1}" || exit 1
    # create container
    archboot-"${_ARCH}"-create-container.sh "${_W_DIR}" -cc --install-source="${2}" || exit 1
    _create_archboot_db "${_W_DIR}${_CACHEDIR}"
    #shellcheck disable=SC1090
    . "${_W_DIR}/etc/archboot/${_ARCH}.conf"
    #shellcheck disable=SC2116,SC2046,2086
    _KERNEL="$(echo ${_W_DIR}${_KERNEL})"
    _NAME="archboot-$(date +%Y.%m.%d-%H.%M)-$(_kver "${_KERNEL}")"
    if ! [[ "${_RUNNING_ARCH}" == "${_ARCH}" ]]; then
        ### to speedup build for riscv64 and aarch64 on x86_64, run compressor on host system
        echo "Generating initramdisks..."
        # init ramdisk
        _create_initrd_dir "${_ARCH}-init.conf"
        _create_cpio "${_W_DIR}/tmp/initrd" "../../init-${_ARCH}.img"
        if ! [[ "${_ARCH}" == "riscv64" ]]; then
            # local ramdisk
            _create_initrd_dir "${_CONFIG_LOCAL}"
            _create_fw_cpio
            mv "${_W_DIR}/firmware" "${_W_DIR}/firmware-local"
            echo "Generating local initramfs..."
            _create_cpio "${_W_DIR}/tmp/initrd" "../../initrd-local-${_ARCH}.img"
            # latest ramdisk
            _create_initrd_dir "${_CONFIG_LATEST}"
            _create_fw_cpio
            mv "${_W_DIR}/firmware" "${_W_DIR}/firmware-latest"
            echo "Generating latest initramfs..."
            _create_cpio "${_W_DIR}/tmp/initrd" "../../initrd-latest-${_ARCH}.img"
        fi
        # normal ramdisk
        _create_initrd_dir "${_ARCH}.conf"
        _create_fw_cpio
        echo "Generating normal initramfs..."
        _create_cpio "${_W_DIR}/tmp/initrd" "../../initrd-${_ARCH}.img"
    fi
    # riscv64 does not support kexec at the moment
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp container tmpfs, else weird things could happen
        # removing not working lvm2 from latest and local image first
        echo "Generating local ISO..."
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g -s \
            -c=${_CONFIG_LOCAL} -i=${_NAME}-local-${_ARCH}" || exit 1
        echo "Generating latest ISO..."
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_ARCH}-iso.sh -g \
            -c=${_CONFIG_LATEST} -i=${_NAME}-latest-${_ARCH}" || exit 1
    fi
    echo "Generating normal ISO..."
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_ARCH}-iso.sh -g -s \
        -i=${_NAME}-${_ARCH}" || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>"${_NO_LOG}"
    mv "${_W_DIR}"/*.img ./ &>"${_NO_LOG}"
    # create boot directory with ramdisks
    echo "Creating boot directory..."
    mkdir -p boot/
    mv init-* boot/
    if [[ "${_ARCH}" == "riscv64" ]]; then
        for i in *.img; do
            if  echo "${i}" | rg -v 'local' | rg -vq 'latest'; then
                mv "${_KERNEL}" boot/
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD}"
            elif echo "${i}" | rg -q 'latest'; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD_LATEST}"
            elif echo "${i}" | rg -q 'local'; then
                mcopy -m -i "${i}"@@1048576 ::/"${_INITRD}" ./"${_INITRD_LOCAL}"
            fi
        done
    else
        for i in *.iso; do
            if  echo "${i}" | rg -v 'local' | rg -vq 'latest'; then
                mv "${_W_DIR}/${_AMD_UCODE}" boot/
                mv "${_KERNEL}" boot/
                if [[ "${_ARCH}" == "aarch64" ]]; then
                    # replace aarch64 Image.gz with Image kernel for UKI
                    # compressed image is not working at the moment
                    _KERNEL="$(echo "${_KERNEL}" | sd '\.gz' '')"
                    mv "${_KERNEL}" boot/
                else
                    mv "${_W_DIR}/${_INTEL_UCODE}" boot/
                fi
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD}"
                mcopy -m -i  mcopy -m -i efi.img ::/boot/firmware boot/
            elif echo "${i}" | rg -q 'latest'; then
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD_LATEST}"
            elif echo "${i}" | rg -q 'local'; then
                isoinfo -R -i "${i}" -x /efi.img 2>"${_NO_LOG}" > efi.img
                mcopy -m -i efi.img ::/"${_INITRD}" ./"${_INITRD_LOCAL}"
            fi
            rm efi.img
        done
        # add ucode licenses
        mkdir -p licenses/
        mv "${_W_DIR}/usr/share/licenses/amd-ucode" licenses/
        [[ "${_ARCH}" == "x86_64" ]] && mv "${_W_DIR}/usr/share/licenses/intel-ucode" licenses/
        echo "Generating Unified Kernel Images..."
        _KERNEL="boot/${_KERNEL##*/}"
        [[ -n "${_INTEL_UCODE}" ]] && _INTEL_UCODE="--initrd=${_INTEL_UCODE}"
        _AMD_UCODE="--initrd=${_AMD_UCODE}"
        rm -r "${_W_DIR:?}"/boot
        mv boot "${_W_DIR}"
        for initrd in ${_INITRD} ${_INITRD_LATEST} ${_INITRD_LOCAL}; do
            _FW_IMG=()
            # all firmwares
            if [[ "${initrd}" == "${_INITRD}" ]]; then
                _UKI="/boot/${_NAME}-${_ARCH}"
                for i in "${_W_DIR}"/boot/firmware/*; do
                    _FW_IMG+=(--initrd=/boot/firmware/"$(basename "${i}")")
                done
            fi
            [[ "${initrd}" == "${_INITRD_LATEST}" ]] && _UKI="/boot/${_NAME}-latest-${_ARCH}"
            [[ "${initrd}" == "${_INITRD_LOCAL}" ]] && _UKI="/boot/${_NAME}-local-${_ARCH}"
            # only kms firmwares
            if [[ "${initrd}" == "${_INITRD_LOCAL}" || "${initrd}" == "${_INITRD_LATEST}" ]]; then
                for i in amdgpu i915 nvidia radeon xe; do
                    _FW_IMG+=(--initrd=/boot/firmware/"${i}".img)
                done
            fi
            #shellcheck disable=SC2086,SC2068
            ${_NSPAWN} "${_W_DIR}" /usr/lib/systemd/ukify build --linux="${_KERNEL}" \
                ${_INTEL_UCODE} ${_AMD_UCODE} --initrd="${initrd}" ${_FW_IMG[@]} --cmdline="${_CMDLINE}" \
                --os-release=@"${_OSREL}" --splash="${_SPLASH}" --output="${_UKI}.efi" &>"${_NO_LOG}" || exit 1
        done
        # fix permission and timestamp
        mv "${_W_DIR}"/boot ./
        chmod 644 boot/*.efi
    fi
    touch boot/*
    echo "Generating Release.txt..."
    ${_NSPAWN} "${_W_DIR}" pacman -Sy "${_W_DIR}" &>"${_NO_LOG}"
    (echo "ARCHBOOT - ARCH LINUX INSTALLATION / RESCUE SYSTEM"
    echo "archboot.com | (c) 2006 - $(date +%Y)"
    echo "Tobias Powalowski <tpowa@archlinux.org>"
    echo ""
    echo "The release is based on these main packages:"
    echo "Archboot: $(${_NSPAWN} "${_W_DIR}" pacman -Qi "${_ARCHBOOT}" |\
    rg -o 'Version.* (.*)\r' -r '$1')"
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub: $(${_NSPAWN} "${_W_DIR}" pacman -Qi grub |\
                                     rg -o 'Version.* (.*)\r' -r '$1')"
    echo "Linux: $(${_NSPAWN} "${_W_DIR}" pacman -Qi linux |\
    rg -o 'Version.* (.*)\r' -r '$1')"
    echo "Pacman: $(${_NSPAWN} "${_W_DIR}" pacman -Qi pacman |\
    rg -o 'Version.* (.*)\r' -r '$1')"
    echo "Systemd: $(${_NSPAWN} "${_W_DIR}" pacman -Qi systemd |\
    rg -o 'Version.* (.*)\r' -r '$1')"
    echo ""
    if [[ -f "${_W_DIR}"/etc/archboot/ssh/archboot-key ]]; then
        cat "${_W_DIR}"/etc/archboot/ssh/archboot-key
    fi
    echo ""
    echo "---Complete Package List---"
    ${_NSPAWN} "${_W_DIR}" pacman -Q | sd '\r|\x1b\[[0-9;]*m|\x1b\[.[0-9]+[h;l]' '') >>Release.txt
    echo "Removing container ${_W_DIR}..."
    rm -r "${_W_DIR}"
    if [[ "${_ARCH}" == "riscv64" ]]; then
        echo "Creating img/ directory..."
        mkdir img
        mv ./*.img img/
    else
        echo "Creating iso/ directory..."
        mkdir iso
        mv ./*.iso iso/
        echo "Creating uki/ directory..."
        mkdir uki
        mv boot/*.efi uki/
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
