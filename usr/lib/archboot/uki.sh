#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_AMD_UCODE="/boot/amd-ucode.img"
_INTEL_UCODE="/boot/intel-ucode.img"
_SPLASH="/usr/share/archboot/uki/archboot-background.bmp"
_OSREL="/usr/share/archboot/base/etc/os-release"
_CONFIG_DIR="/etc/archboot"
_UKIDIR="$(mktemp -d UKIDIR.XXX)"

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create ${_ARCH} UKI Image\e[m"
    echo -e "\e[1m--------------------------------------\e[m"
    echo "This will create an Archboot UKI image."
    echo
    echo "Options:"
    echo -e " \e[1m-g\e[m              Starting generation of image."
    echo -e " \e[1m-c=CONFIG\e[m       Which CONFIG should be used."
    echo "                 ${_CONFIG_DIR} includes the config files"
    echo "                 default=${_ARCH}.conf"
    echo -e " \e[1m-i=IMAGENAME\e[m    Your IMAGENAME."
    echo
    echo -e "Usage: \e[1m${_BASENAME} <options>\e[m"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -c=*|--c=*) _CONFIG="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
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
    _KERNEL="$(echo ${_KERNEL})"
    #shellcheck disable=SC2154
    [[ -z "${_UKI}" ]] && _UKI="archboot-$(date +%Y.%m.%d-%H.%M)-$(_kver "${_KERNEL}")-${_ARCH}".efi
}

_prepare_kernel_initramfs() {
    # needed to hash the kernel for secureboot enabled systems
    echo "Preparing kernel..."
    install -m644 "${_KERNEL}" "${_UKIDIR}/kernel"
    _INITRD="initrd-${_ARCH}.img"
    echo "Running archboot-cpio.sh for ${_INITRD}..."
    #shellcheck disable=SC2154
    archboot-cpio.sh -c "${_CONFIG}" -k "${_KERNEL}" \
                     -g "${_UKIDIR}/${_INITRD}" || exit 1
}

_prepare_ucode() {
    # only x86_64
    if [[ "${_ARCH}" == "x86_64" ]]; then
        echo "Preparing intel-ucode..."
        cp "${_INTEL_UCODE}" "${_UKIDIR}/"
    fi
    echo "Preparing amd-ucode..."
    cp "${_AMD_UCODE}" "${_UKIDIR}/"
}

_prepare_background() {
    echo "Preparing UKI splash..."
    cp "${_SPLASH}" "${_UKIDIR}/splash.png"
}

_prepare_osrelease() {
    echo "Preparing os-release..."
    cp "${_OSREL}" "${_UKIDIR}/os-release"
}

_reproducibility() {
    # Reproducibility: set all timestamps to 0
    fd . "${_UKIDIR}" -u --min-depth 1 -X touch -hcd "@0"
}

_systemd_ukify() {
    echo "Generating ${_ARCH} UKI image..."
    pushd "${_UKIDIR}" &>"${_NO_LOG}" || exit 1
    [[ "${_ARCH}" == "aarch64" ]] && _CMDLINE="console=ttyS0,115200 console=tty0 audit=0 systemd.show_status=auto"
    [[ "${_ARCH}" == "aarch64" ]] && _CMDLINE="nr_cpus=1 console=ttyAMA0,115200 console=tty0 loglevel=4 audit=0 systemd.show_status=auto"
    [[ -n "${_INTEL_UCODE}" ]] && _INTEL_UCODE="--initrd=intel-ucode"
    [[ -n "${_AMD_UCODE}" ]] && _AMD_UCODE="--initrd=amd-ucode"
    /usr/lib/systemd/ukify build --linux=kernel \
        ${_INTEL_UCODE} ${_AMD_UCODE} --initrd="${_INITRD}" --cmdline=@"${_CMDLINE}" \
        --os-release=@os-release --splash=splash.png --output=../"${_UKI}" &>"${_NO_LOG}" || exit 1
    popd &>"${_NO_LOG}" || exit 1
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
