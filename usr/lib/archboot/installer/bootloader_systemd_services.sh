#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_efistub_copy_to_efisys() {
    if ! [[ "${_UEFISYS_MP}" == "boot" ]]; then
        # clean and copy to efisys
        [[ -d "${_DESTDIR}/${_UEFISYS_MP}/${_UEFISYS_PATH}" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/${_UEFISYS_PATH}"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_KERNEL}"
        cp -f "${_DESTDIR}/boot/${_VMLINUZ}" "${_DESTDIR}/${_UEFISYS_MP}/${_KERNEL}"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD}"
        cp -f "${_DESTDIR}/boot/${_INITRAMFS}" "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD}"
        if [[ -n "${_INITRD_UCODE}" ]]; then
            rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD_UCODE}"
            cp -f "${_DESTDIR}/boot/${_UCODE}" "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD_UCODE}"
        fi
        sleep 2
        _progress "50" "Enable automatic copying to EFI SYSTEM PARTITION on installed system..."
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Path]
PathChanged=/boot/${_VMLINUZ}
PathChanged=/boot/${_INITRAMFS}
CONFEOF
        if [[ -n "${_UCODE}" ]]; then
            echo "PathChanged=/boot/${_UCODE}" >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
        fi
        cat << CONFEOF >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
Unit=efistub_copy.service
[Install]
WantedBy=multi-user.target
CONFEOF
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Service]
Type=oneshot
ExecStart=/usr/bin/cp -f /boot/${_VMLINUZ} /${_UEFISYS_MP}/${_KERNEL}
ExecStart=/usr/bin/cp -f /boot/${_INITRAMFS} /${_UEFISYS_MP}/${_INITRD}
CONFEOF
        if [[ -n "${_INITRD_UCODE}" ]]; then
            echo "ExecStart=/usr/bin/cp -f /boot/${_UCODE} /${_UEFISYS_MP}/${_INITRD_UCODE}" \
            >> "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
        fi
        ${_NSPAWN} systemctl enable efistub_copy.path &>"${_NO_LOG}"
        sleep 2
        _progress "100" "Automatic Syncing to EFI SYSTEM PARTITIOM completed."
        sleep 2
    fi
    # reset _VMLINUZ on aarch64
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        _VMLINUZ="Image.gz"
    fi
}

_uki_autobuild() {
    sleep 2
    _progress "50" "Enable automatic UKI creation on installed system..."
    cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/run_ukify.path"
[Unit]
Description=Run systemd ukify
[Path]
PathChanged=/boot/${_INITRAMFS}
PathChanged=/boot/${_UCODE}
Unit=run_ukify.service
[Install]
WantedBy=multi-user.target
CONFEOF
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/run_ukify.service"
[Unit]
Description=Run systemd ukify
[Service]
Type=oneshot
ExecStart="/usr/lib/systemd/ukify build --config=/etc/ukify.conf --output ${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi"
CONFEOF
    ${_NSPAWN} systemctl enable run_ukify.path &>"${_NO_LOG}"
}
