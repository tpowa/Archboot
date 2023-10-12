#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# archboot-cpio.sh - modular tool for building initramfs images
# simplified, stripped down, optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

shopt -s extglob

. /usr/lib/archboot/common.sh
. /usr/lib/archboot/cpio.sh
# needed files/directories
_CONFIG=""
_INITCPIO=/lib/initcpio/install
# options and runtime data
_GENERATE_IMAGE=""
_TARGET_DIR=""
declare -A  _addedmodules _modpaths
# Sanitize environment further
# GREP_OPTIONS="--color=always" will break everything
# CDPATH can affect cd and pushd
# LIBMOUNT_* options can affect findmnt and other tools
unset GREP_OPTIONS CDPATH "${!LIBMOUNT_@}"

_usage() {
    cat <<EOF
ARCHBOOT CPIO
-------------
Tool for creating an archboot initramfs image.

 -h               Display this message and exit

 -c <config>      Use <config> file
 -k <kernel>      Use specified <kernel>

 -g <path>        Generate cpio image and write to specified <path>
 -d <dir>         Generate image into <dir>

usage: ${0##*/} <options>
EOF
}

# The function is called from the EXIT trap
# shellcheck disable=SC2317
cleanup() {
    local err="${1:-$?}"
    if [[ -n "$_d_workdir" ]]; then
        rm -rf -- "$_d_workdir"
    fi
    exit "$err"
}

build_image() {
    local out="$1" compressout="$1" compress="$2" errmsg pipestatus
    case "$compress" in
        cat)
            msg "Creating uncompressed initcpio image: '%s'" "$out"
            unset COMPRESSION_OPTIONS
            ;;
        *)
            msg "Creating %s-compressed initcpio image: '%s'" "$compress" "$out"
            ;;&
        xz)
            COMPRESSION_OPTIONS=('-T0' '--check=crc32' "${COMPRESSION_OPTIONS[@]}")
            ;;
        lz4)
            COMPRESSION_OPTIONS=('-l' "${COMPRESSION_OPTIONS[@]}")
            ;;
        zstd)
            COMPRESSION_OPTIONS=('-T0' "${COMPRESSION_OPTIONS[@]}")
            ;;
    esac
    if [[ -f "$out" ]]; then
        local curr_size space_left_on_device
        curr_size="$(stat --format="%s" "$out")"
        space_left_on_device="$(($(stat -f --format="%a*%S" "$out")))"
        # check if there is enough space on the device to write the image to a tempfile, fallback otherwise
        # this assumes that the new image is not more than 1¼ times the size of the old one
        (( $((curr_size + (curr_size/4))) < space_left_on_device )) && compressout="$out".tmp
    fi
    pushd "$BUILDROOT" >"${_NO_LOG}" || return
    # Reproducibility: set all timestamps to 0
    find . -mindepth 1 -execdir touch -hcd "@0" "{}" +
    # If this pipeline changes, |pipeprogs| below needs to be updated as well.
    find . -mindepth 1 -printf '%P\0' |
            sort -z |
            LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            $compress "${COMPRESSION_OPTIONS[@]}" > "$compressout"
    pipestatus=("${PIPESTATUS[@]}")
    pipeprogs=('find' 'sort' 'bsdtar (step 1)' 'bsdtar (step 2)' "$compress")
    popd >"${_NO_LOG}" || return
    for (( i = 0; i < ${#pipestatus[*]}; ++i )); do
        if (( pipestatus[i] )); then
            errmsg="${pipeprogs[i]} reported an error"
            break
        fi
    done
    if (( _builderrors )); then
        warning "errors were encountered during the build. The image may not be complete."
    fi
    if [[ -n "$errmsg" ]]; then
        error "Image generation FAILED: '%s'" "$errmsg"
        return 1
    elif (( _builderrors == 0 )); then
        msg "Image generation successful"
    fi
    # sync and rename as we only wrote to a tempfile so far to ensure consistency
    if [[ "$compressout" != "$out" ]]; then
        sync -d -- "$compressout"
        mv -f -- "$compressout" "$out"
    fi
}

preload_builtin_modules() {
    local modname field value
    # Prime the _addedmodules list with the builtins for this kernel.
    # kmod>=27 and kernel >=5.2 required!
    while IFS=.= read -rd '' modname field value; do
        _addedmodules[${modname//-/_}]=2
        case "$field" in
            alias)
                _addedmodules["${value//-/_}"]=2
                ;;
        esac
    done <"$_d_kmoduledir/modules.builtin.modinfo"
}

if [[ -z "$1" ]]; then
    _usage
    exit 0
fi
_root_check

while :; do
    case "$1" in
        -c)
            shift
            ${_CONFIG}="$1"
            ;;
        -k)
            shift
            KERNEL="$1"
            ;;
        -d)
            shift
            ${_TARGET_DIR}="$1"
            ;;
        -g)
            shift
            [[ -d "$1" ]] && die 'Invalid image path -- must not be a directory'
            if ! ${_GENERATE_IMAGE}="$(readlink -f "$1")" || [[ ! -e "${_GENERATE_IMAGE%/*}" ]]; then
                die "Unable to write to path: '%s'" "$1"
            fi
            ;;
        -h)
            _usage
            exit 0
            ;;
        --)
            shift
            break 2
            ;;
    esac
    shift
done

#shellcheck disable="SC1090"
! . "${_CONFIG}" 2>"${_NO_LOG}" && die "Failed to read configuration '%s'" "${_CONFIG}"
if [[ -z "${KERNEL}" ]]; then
    msg "Trying to autodetect ${_RUNNING_ARCH} kernel..."
    [[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && KERNEL="/usr/lib/modules/*/vmlinuz"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && KERNEL="/boot/Image.gz"
fi
# allow * in config
#shellcheck disable=SC2116,2086
KERNEL="$(echo ${KERNEL})"
msg "Using kernel: ${KERNEL}"
if [[ ! -f "${KERNEL}" ]]; then
    die "kernel image does not exist!"
fi
_KERNELVERSION="$(_kver "${KERNEL}")"
_d_kmoduledir="/lib/modules/${_KERNELVERSION}"
[[ -d "$_d_kmoduledir" ]] || die "'$_d_kmoduledir' is not a valid kernel module directory"
_d_workdir="$(initialize_buildroot "${_KERNELVERSION}" "${_TARGET_DIR}")" || exit 1
BUILDROOT="${_TARGET_DIR}:-$_d_workdir/root}"
_hooks=("${HOOKS[@]}")
if (( ${#_hooks[*]} == 0 )); then
    die "Invalid config: No hooks found"
fi
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    # check for permissions. if the image doesn't already exist,
    # then check the directory
    if [[ ( -e ${_GENERATE_IMAGE} && ! -w ${_GENERATE_IMAGE} ) ||
            ( ! -d ${_GENERATE_IMAGE%/*} || ! -w ${_GENERATE_IMAGE%/*} ) ]]; then
        die "Unable to write to '%s'" "${_GENERATE_IMAGE}"
    fi
    msg "Starting build: '%s'" "${_KERNELVERSION}"
elif [[ -n "${_TARGET_DIR}" ]]; then
    msg "Starting build: '%s'" "${_KERNELVERSION}"
else
    msg "Starting dry run: '%s'" "${_KERNELVERSION}"
fi
# set functrace and trap to catch errors in add_* functions
declare -i _builderrors=0
preload_builtin_modules
map run_build_hook "${_hooks[@]}" || (( ++_builderrors ))
install_modules "${!_modpaths[@]}"
# this is simply a nice-to-have -- it doesn't matter if it fails.
ldconfig -r "$BUILDROOT" &>"${_NO_LOG}"
# remove /var/cache/ldconfig/aux-cache for reproducability
rm -f -- "$BUILDROOT/var/cache/ldconfig/aux-cache"
# Set umask to create initramfs images as 600
umask 077
if [[ -n "${_GENERATE_IMAGE}" ]]; then
    build_image "${_GENERATE_IMAGE}" "${COMPRESSION}" || exit 1
elif [[ -n "${_TARGET_DIR}" ]]; then
    msg "Build complete."
else
    msg "Dry run complete, use -g IMAGE to generate a real image"
fi
exit $(( !!_builderrors ))

# vim: set ft=sh ts=4 sw=4 et:
