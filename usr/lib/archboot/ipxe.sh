#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_CODESIGN_CERT="${_CERT_DIR}/codesign.crt"
_CODESIGN_KEY="${_CERT_DIR}/codesign.key"
_CA_CERT="${_CERT_DIR}/ca.crt"

_usage_certs() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - IPXE Certs\e[m"
    echo -e "\e[1m---------------------\e[m"
    echo "Create Archboot -IPXE Root Certs for a chain of trust."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}

_usage_sign() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Sign IPXE File\e[m"
    echo -e "\e[1m---------------------\e[m"
    echo "Create IPXE signature file with custom chain of trust."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <file>\e[m"
    exit 0
}

_cert_dir_check() {
    if [[ -d "${_CERT_DIR}" ]]; then
        echo "${_CERT_DIR} already exists! Do you want to create a new Archboot IPXE chain of trust (y/N)?"
        read -r _NEW
        if [[ "${_NEW}" == "y" ]]; then
            echo "Backup old certificates to /etc/archboot/ipxe.backup.$(date -I)"
            mv /etc/archboot/ipxe "/etc/archboot/ipxe.backup.$(date -I)"
        else
            exit 1
        fi
    fi
}

_chain_of_trust() {
    # instructions from https://ipxe.org/crypto
    # create own private root CA, only personal change to 1000 days
    mkdir -p "${_CERT_DIR}"
    pushd "${_CERT_DIR}" || exit 1
    openssl req -x509 -newkey rsa:2048 -out ca.crt -keyout ca.key -days 1000 || exit 1
    echo 01 > ca.srl
    touch ca.idx
    mkdir signed
    cat << EOF > ca.cnf
default_ca             = ca_default

[ ca_default ]
certificate            = ca.crt
private_key            = ca.key
serial                 = ca.srl
database               = ca.idx
new_certs_dir          = signed
default_md             = default
policy                 = policy_anything
preserve               = yes
default_days           = 1000
unique_subject         = no

[ policy_anything ]
countryName            = optional
stateOrProvinceName    = optional
localityName           = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = optional
emailAddress           = optional

[ cross ]
basicConstraints       = critical,CA:true
keyUsage               = critical,cRLSign,keyCertSign

[ codesigning ]
keyUsage                = digitalSignature
extendedKeyUsage        = codeSigning
EOF
    openssl req -newkey rsa -keyout server.key -out server.req || exit 1
    openssl ca -config ca.cnf -in server.req -out server.crt || exit 1
    openssl req -newkey rsa -keyout codesign.key -out codesign.req || exit 1
    openssl ca -config ca.cnf -extensions codesigning -in codesign.req -out codesign.crt || exit 1
    popd || exit 1
}
