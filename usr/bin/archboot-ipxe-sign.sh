#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Tobias Powalowski <tpowa@archlinux.org>
# archboot wrapper for signing ipxe files
_IPXE_CERT_DIR=/etc/archboot/ipxe
_IPXE_PASSPHRASE=${_IPXE_CERT_DIR}/ipxe.passphrase
_CODESIGN_CERT="${_IPXE_CERT_DIR}/codesign.crt"
_CODESIGN_KEY="${_IPXE_CERT_DIR}/codesign.key"
_CA_CERT="${_IPXE_CERT_DIR}/ca.crt"

openssl cms -sign -binary -noattr -in "${1}" \
            -signer "${_CODESIGN_CERT}" \
            -inkey "${_CODESIGN_KEY}" \
            -certfile "${_CA_CERT}" \
            --passin file:"${_IPXE_PASSPHRASE}" \
            -outform DER -out "${1}".sig
