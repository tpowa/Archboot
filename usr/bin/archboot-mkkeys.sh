#!/usr/bin/env bash
# Copyright (c) 2015 by Roderick W. Smith
# Licensed under the terms of the GPL v3
# replaced GUID with uuidgen Tobias Powalowski - <tpowa@archlinux.org>
_GUID="$(uuidgen --random)"
_NO_LOG=/dev/null
if [[ -z "${1}" ]]; then
  echo -n "Enter a Common Name to embed in the keys: "
fi
read -r _NAME
echo ""
echo "Creating keys with Common Name: ${_NAME} ..."
openssl req -new -x509 -newkey rsa:4096 -subj "/CN=${_NAME} PK/" -keyout PK.key \
        -out PK.crt -days 3650 -nodes -sha256 &>"${_NO_LOG}"
openssl req -new -x509 -newkey rsa:4096 -subj "/CN=${_NAME} KEK/" -keyout KEK.key \
        -out KEK.crt -days 3650 -nodes -sha256 &>"${_NO_LOG}"
openssl req -new -x509 -newkey rsa:4096 -subj "/CN=${_NAME} DB/" -keyout DB.key \
        -out DB.crt -days 3650 -nodes -sha256 &>"${_NO_LOG}"
openssl x509 -in PK.crt -out PK.cer -outform DER &>"${_NO_LOG}"
openssl x509 -in KEK.crt -out KEK.cer -outform DER &>"${_NO_LOG}"
openssl x509 -in DB.crt -out DB.cer -outform DER &>"${_NO_LOG}"
echo "${_GUID}" > GUID.txt
cert-to-efi-sig-list -g "${_GUID}" PK.crt PK.esl
cert-to-efi-sig-list -g "${_GUID}" KEK.crt KEK.esl
cert-to-efi-sig-list -g "${_GUID}" DB.crt DB.esl
rm -f noPK.esl
: > noPK.esl
sign-efi-sig-list -g "${_GUID}" -k PK.key -c PK.crt PK PK.esl PK.auth &>"${_NO_LOG}"
sign-efi-sig-list -g "${_GUID}" -k PK.key -c PK.crt PK noPK.esl noPK.auth &>"${_NO_LOG}"
sign-efi-sig-list -g "${_GUID}" -k PK.key -c PK.crt KEK KEK.esl KEK.auth &>"${_NO_LOG}"
sign-efi-sig-list -g "${_GUID}" -k KEK.key -c KEK.crt db DB.esl DB.auth &>"${_NO_LOG}"
chmod 0600 ./*.key
echo ""
echo "For use with KeyTool, copy the *.auth and *.esl files to a FAT USB"
echo "flash drive or to your EFI System Partition (ESP)."
echo "For use with most UEFIs' built-in key managers, copy the *.cer files;"
echo "but some UEFIs require the *.auth files."
echo ""
