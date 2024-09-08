#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_UKIDIR="$(mktemp -d UKIDIR.XXX)"

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create ${_ARCH} UKI Image\e[m"
    echo -e "\e[1m--------------------------------------\e[m"
    echo "This will create an Archboot UKI image."
    echo
    echo "Options:"
    echo -e " \e[1m-g\e[m              Start generation of an UKI image."
    echo -e " \e[1m-c=CONFIG\e[m       Which CONFIG should be used."
    echo "                 ${_CONFIG_DIR} includes the config files"
    echo "                 default=${_ARCH}.conf"
    echo -e " \e[1m-cli='options'\e[m  Your custom kernel commandline options."
    echo -e " \e[1m-i=UKI\e[m          Your custom UKI image name."
    echo
    echo -e "Usage: \e[1m${_BASENAME} <options>\e[m"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -c=*|--c=*) _CONFIG="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
            -cli=*) _CMDLINE="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
            -i=*|--i=*) _UKI="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
            *) _usage ;;
        esac
        shift
    done
}

_config() {
    # set defaults, if nothing given
    [[ -z "${_CONFIG}" ]] && _CONFIG="${_ARCH}.conf"
    _CONFIG="${_CONFIG_DIR}/${_CONFIG}"
    #shellcheck disable=SC1090
    . "${_CONFIG}"
    #shellcheck disable=SC2116,2086
    # aarch64 .gz kernel is not supported!
    _KERNEL="$(echo ${_KERNEL} | sd '\.gz' '')"
    #shellcheck disable=SC2154
    [[ -z "${_UKI}" ]] && _UKI="archboot-$(date +%Y.%m.%d-%H.%M)-$(_kver "${_KERNEL}")-${_ARCH}"
}

_prepare_initramfs() {
    # needed to hash the kernel for secureboot enabled systems
    echo "Preparing initramfs..."
    _INITRD="${_UKIDIR}/initrd.img"
    echo "Running archboot-cpio.sh for ${_INITRD}..."
    #shellcheck disable=SC2154
    archboot-cpio.sh -c "${_CONFIG}" -k "${_KERNEL}" \
                     -g "${_INITRD}" || exit 1
}

_systemd_ukify() {
    echo "Generating ${_ARCH} UKI image..."
    [[ -n "/${_INTEL_UCODE}" ]] && _INTEL_UCODE="--initrd=/${_INTEL_UCODE}"
    _AMD_UCODE="--initrd=/${_AMD_UCODE}"
    #shellcheck disable=SC2086
    /usr/lib/systemd/ukify build --linux="${_KERNEL}" \
        ${_INTEL_UCODE} ${_AMD_UCODE} --initrd="${_INITRD}" --cmdline="${_CMDLINE}" \
        --os-release=@"${_OSREL}" --splash="${_SPLASH}" --output="${_UKI}.efi" &>"${_NO_LOG}" || exit 1
}

_create_cksum() {
    ## create b2sums.txt
    echo "Generating b2sum..."
    [[ -f  "b2sums.txt" ]] && rm "b2sums.txt"
    [[ "$(echo ./*.iso)" == "./*.efi" ]] || cksum -a blake2b ./*.efi > "b2sums.txt"
}

_cleanup_uki() {
    # cleanup
    echo "Removing ${_UKIDIR}..."
    [[ -d "${_UKIDIR}" ]] && rm -r "${_UKIDIR}"
}
