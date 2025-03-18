#!/bin/bash
#shellcheck disable=SC2044
for i in $(find ../release/"${1}"/latest/ipxe/ ! -name '*.sig' ! -name '*.html' ! -name '*.txt' ! -name 'init-*' ! -name 'ipxe' ! -name 'Image'); do
	ln -s ../"${i}" "${1}"/"$(basename "${i}")"
	ln -s ../"${i}".sig "${1}"/"$(basename "${i}")".sig
done
