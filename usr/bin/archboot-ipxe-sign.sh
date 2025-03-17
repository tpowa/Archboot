#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tobias Powalowski <tpowa@archlinux.org>
# create IPXE signature file with custom chain of trust
. /etc/archboot/defaults
. /usr/lib/archboot/ipxe.sh
[[ -z "${1}" ]] && _usage_sign
openssl cms -sign -binary -noattr -in "${1}" \
            -signer "${_CODESIGN_CERT}" \
            -inkey "${_CODESIGN_KEY}" \
            -certfile "${_CA_CERT}" \
            --passin file:"${_IPXE_PASSPHRASE}" \
            -outform DER -out "${1}".sig || exit 1
