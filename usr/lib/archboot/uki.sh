#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create ${_ARCH} UKI Image\e[m"
    echo -e "\e[1m----------------------------------------\e[m"
    echo "Create an Archboot UKI image: <name>.efi"
    echo
    echo "Options:"
    echo -e " \e[1m-g\e[m              Start generation of an UKI image."
    echo -e " \e[1m-c=CONFIG\e[m       CONFIG from ${_CONFIG_DIR}: default=${_ARCH}.conf"
    echo -e " \e[1m-cli='options'\e[m  Customize kernel commandline options"
    echo -e " \e[1m-i=UKI\e[m          Customize UKI image name"
    echo
    echo -e "Usage: \e[1m${_BASENAME} <options>\e[m"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -c=*|--c=*) _CONFIG="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
            -cli=*) _CMDLINE="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
            -i=*|--i=*) _UKI="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
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
    # aarch64 .gz kernel is not supported!
    #shellcheck disable=SC2086
    _KERNEL="$(echo ${_KERNEL} | sd '\.gz' '')"
    [[ -z "${_UKI}" ]] && _UKI="archboot-$(date +%Y.%m.%d-%H.%M)-$(_kver "${_KERNEL}")-${_ARCH}"
}

_prepare_initramfs() {
    # needed to hash the kernel for secureboot enabled systems
    echo "Preparing initramfs..."
    _INITRD="${_UKIDIR}/initrd.img"
    echo "Running archboot-cpio.sh for ${_INITRD}..."
    archboot-cpio.sh -c "${_CONFIG}" -k "${_KERNEL}" \
                     -g "${_INITRD}" || exit 1
}

_systemd_ukify() {
    echo "Generating ${_ARCH} UKI image..."
    [[ -n "${_INTEL_UCODE}" ]] && _INTEL_UCODE=(--initrd=/"${_INTEL_UCODE}")
    _AMD_UCODE=(--initrd=/"${_AMD_UCODE}")
    /usr/lib/systemd/ukify build --linux="${_KERNEL}" \
        "${_INTEL_UCODE[@]}" "${_AMD_UCODE[@]}" --initrd="${_INITRD}" --cmdline="${_CMDLINE}" \
        --os-release=@"${_OSREL}" --splash="${_SPLASH}" --output="${_UKI}.efi" &>"${_NO_LOG}" || exit 1
}

_cleanup_uki() {
    # cleanup
    echo "Removing ${_UKIDIR}..."
    [[ -d "${_UKIDIR}" ]] && rm -r "${_UKIDIR}"
}
