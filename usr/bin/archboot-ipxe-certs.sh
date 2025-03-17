#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/ipxe.sh
[[ -z "${1}" || "${1}" != "run" ]] && _usage_certs
_root_check
_cert_dir_check || exit 1
_chain_of_trust || exit 1

