#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_uki_autobuild() {
    read -r -t 2
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
