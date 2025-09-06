#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/uki.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
[[ "${_GENERATE}" == "1" ]] || _usage
_root_check
_architecture_check
_config
_UKIDIR="$(mktemp -d UKIDIR.XXX)"
echo "Starting UKI creation..."
_prepare_initramfs || exit 1
_systemd_ukify || exit 1
_create_cksum "-d 1 .efi"
_cleanup_uki || exit 1
echo "Finished UKI creation."
