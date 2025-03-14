#!/usr/bin/env bash
# Tobias Powalowski <tpowa@archlinux.org>
# all commands from https://ipxe.org/crypto
# create own private root CA, only personal change to 1000 days
openssl req -x509 -newkey rsa:2048 -out ca.crt -keyout ca.key -days 1000
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
openssl req -newkey rsa -keyout server.key -out server.req
openssl ca -config ca.cnf -in server.req -out server.crt
openssl req -newkey rsa -keyout codesign.key -out codesign.req
openssl ca -config ca.cnf -extensions codesigning -in codesign.req -out codesign.crt
