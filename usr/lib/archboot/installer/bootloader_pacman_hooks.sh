#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_pacman_hook_common() {
    cat << EOF > "${_HOOKNAME}"
[Trigger]
Type = Package
Operation = Upgrade
Target = ${1}

[Action]
EOF
}

_pacman_hook_systemd_bootd() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-systemd-bootd.hook"
    _pacman_hook_common systemd
    cat << EOF >> "${_HOOKNAME}"
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF
    _dialog --title " Automatic SYSTEMD-BOOT Update " --no-mouse --infobox "Automatic SYSTEMD-BOOT update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_limine_bios() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-limine-bios.hook"
    _pacman_hook_common limine
    cat << EOF >> "${_HOOKNAME}"
Description = Update Limine after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "/usr/bin/cp /usr/share/limine/limine-bios.sys /boot/; /usr/bin/limine bios-install '${_PARENT_BOOTDEV}'"
EOF
    _dialog --title " Automatic LIMINE BIOS Update " --no-mouse --infobox "Automatic LIMINE BIOS update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_limine_uefi() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-limine-uefi.hook"
    _pacman_hook_common limine
    cat << EOF >> "${_HOOKNAME}"
Description = Update Limine after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "/usr/bin/cp /usr/share/limine/BOOT${_UEFI_ARCH}.EFI /${_UEFISYS_MP}/EFI/BOOT/;\
/usr/bin/cp /usr/share/limine/BOOT${_UEFI_ARCH}.EFI /${_UEFISYS_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI"
EOF
    _dialog --title " Automatic LIMINE Update " --no-mouse --infobox "Automatic LIMINE update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_refind() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-refind.hook"
    _pacman_hook_common refind
    cat << EOF >> "${_HOOKNAME}"
Description = Update rEFInd after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "/usr/bin/cp /usr/share/refind/refind_${_SPEC_UEFI_ARCH}.efi /${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI;/usr/bin/refind-install"
EOF
    _dialog --title " Automatic rEFInd Update " --no-mouse --infobox "Automatic rEFInd update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_grub_bios() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-grub-bios.hook"
    _pacman_hook_common grub
    cat << EOF >> "${_HOOKNAME}"
Description = Update GRUB after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "grub-install --directory='/usr/lib/grub/i386-pc' --target='i386-pc' --boot-directory='/boot' --recheck '${_BOOTDEV}'"
EOF
    _dialog --title " Automatic GRUB Update " --no-mouse --infobox "Automatic GRUB BIOS update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_grub_uefi() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-grub-uefi.hook"
    _pacman_hook_common grub
    cat << EOF >> "${_HOOKNAME}"
Description = Update GRUB after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "grub-install --directory='/usr/lib/grub/${_GRUB_ARCH}-efi' --target='${_GRUB_ARCH}-efi' --efi-directory='/${_UEFISYS_MP}' --bootloader-id='grub' --boot-directory='/boot' --no-nvram --recheck"
EOF
    _dialog --title " Automatic GRUB Update " --no-mouse --infobox "Automatic GRUB update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_hook_grub_sb() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-grub-uefi-sb.hook"
    _pacman_hook_common grub
    cat << EOF >> "${_HOOKNAME}"
Description = Update GRUB UEFI SB after upgrade...
When = PostTransaction
Exec = /usr/bin/sh -c "/usr/bin/grub-mkstandalone -d '/usr/lib/grub/${_GRUB_ARCH}-efi' -O '${_GRUB_ARCH}-efi' --sbat=/usr/share/grub/sbat.csv --fonts='ter-u16n' --locales='en@quot' --themes='' -o '/${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi' 'boot/grub/grub.cfg=/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}';/usr/bin/sbsign --key '/${_KEYDIR}/MOK/MOK.key' --cert '/${_KEYDIR}/MOK/MOK.crt' --output '/${_UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi' '/${_UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi'"
EOF
    _dialog --title " Automatic GRUB UEFI SB Update " --no-mouse --infobox "Automatic GRUB UEFI SB update has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_pacman_sign() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
    _pacman_hook_common linux
    cat << EOF >> "${_HOOKNAME}"
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbverify --list {} 2>"${_NO_LOG}" | /usr/bin/grep -q "signature certificates"; then /usr/bin/sbsign --key /${_KEYDIR}/MOK/MOK.key --cert /${_KEYDIR}/MOK/MOK.crt --output {} {}; fi' ;
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF
    _dialog --title " Automatic Signing " --no-mouse --infobox "Automatic signing has been enabled successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}
