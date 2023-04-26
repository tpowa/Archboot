#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# archboot-cpio.sh:
# Arch Linux mkinitcpio - modular tool for building initramfs images
# simplified, stripped down, optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

shopt -s extglob

# needed files/directories
_f_functions=/usr/lib/archboot/cpio.sh
_f_config=
_d_install=/lib/initcpio/install
# options and runtime data
_optgenimg=''
_opttargetdir=''
_optosrelease=''
_optquiet=1 _optcolor=1
declare -A  _addedmodules _modpaths
# Sanitize environment further
# GREP_OPTIONS="--color=always" will break everything
# CDPATH can affect cd and pushd
# LIBMOUNT_* options can affect findmnt and other tools
unset GREP_OPTIONS CDPATH "${!LIBMOUNT_@}"

usage() {
    cat <<EOF
ARCHBOOT CPIO
-------------
Tool for creating an archboot initramfs image.

 -c <config>      Use config file
 -g <path>        Generate cpio image and write to specified path
 -h               Display this message and exit
 -k <kernel>      Use specified kernel
 -d <dir>         Write generated image into <dir>

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

resolve_kernver() {
    local kernel="$1"
    if [[ "${kernel:0:1}" != / ]]; then
        echo "$kernel"
        return 0
    fi
    if [[ ! -e "$kernel" ]]; then
        error "specified kernel image does not exist: '%s'" "$kernel"
        return 1
    fi
    kver "$kernel" && return
    error "invalid kernel specified: '%s'" "$1"
    return 1
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
    pushd "$BUILDROOT" >/dev/null || return
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
    popd >/dev/null || return
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
    local -a path
    # Prime the _addedmodules list with the builtins for this kernel. We prefer
    # the modinfo file if it exists, but this requires a recent enough kernel
    # and kmod>=27.
    if [[ -r $_d_kmoduledir/modules.builtin.modinfo ]]; then
        while IFS=.= read -rd '' modname field value; do
            _addedmodules[${modname//-/_}]=2
            case "$field" in
                alias)
                    _addedmodules["${value//-/_}"]=2
                    ;;
            esac
        done <"$_d_kmoduledir/modules.builtin.modinfo"
    elif [[ -r "$_d_kmoduledir/modules.builtin" ]]; then
        while IFS=/ read -ra path; do
            modname="${path[-1]%.ko}"
            _addedmodules["${modname//-/_}"]=2
        done <"$_d_kmoduledir/modules.builtin"
    fi
}

if [[ -z "$1" ]]; then
    usage
    cleanup 0
fi
### check for root
if ! [[ ${UID} -eq 0 ]]; then
    echo "ERROR: Please run as root user!"
    exit 1
fi
# shellcheck source=functions
. "$_f_functions"
_opt_short='c:d:g:hk:'
parseopts "$_opt_short" -- "$@" || exit 1
set -- "${OPTRET[@]}"
unset _opt_short OPTRET
while :; do
    case "$1" in
        -c|--config)
            shift
            _f_config="$1"
            ;;
        -k|--kernel)
            shift
            KERNELVERSION="$1"
            ;;
        -d|--generatedir)
            shift
            _opttargetdir="$1"
            ;;
        -g|--generate)
            shift
            [[ -d "$1" ]] && die 'Invalid image path -- must not be a directory'
            if ! _optgenimg="$(readlink -f "$1")" || [[ ! -e "${_optgenimg%/*}" ]]; then
                die "Unable to write to path: '%s'" "$1"
            fi
            ;;
        -h|--help)
            usage
            cleanup 0
            ;;
        --)
            shift
            break 2
            ;;
    esac
    shift
done
if [[ -t 1 ]] && (( _optcolor )); then
    try_enable_color
fi
# insist that /proc and /dev be mounted (important for chroots)
# NOTE: avoid using mountpoint for this -- look for the paths that we actually
# use in mkinitcpio. Avoids issues like FS#26344.
[[ -e /proc/self/mountinfo ]] || die "/proc must be mounted!"
[[ -e /dev/fd ]] || die "/dev must be mounted!"
if [[ "$KERNELVERSION" != 'none' ]]; then
    KERNELVERSION="$(resolve_kernver "$KERNELVERSION")" || exit 1
    _d_kmoduledir="/lib/modules/$KERNELVERSION"
    [[ -d "$_d_kmoduledir" ]] || die "'$_d_kmoduledir' is not a valid kernel module directory"
fi
_d_workdir="$(initialize_buildroot "$KERNELVERSION" "$_opttargetdir")" || exit 1
BUILDROOT="${_opttargetdir:-$_d_workdir/root}"
# shellcheck source=mkinitcpio.conf
! . "$_f_config" 2>/dev/null && die "Failed to read configuration '%s'" "$_f_config"
_hooks=("${HOOKS[@]}")
if (( ${#_hooks[*]} == 0 )); then
    die "Invalid config: No hooks found"
fi
if [[ -n "$_optgenimg" ]]; then
    # check for permissions. if the image doesn't already exist,
    # then check the directory
    if [[ ( -e $_optgenimg && ! -w $_optgenimg ) ||
            ( ! -d ${_optgenimg%/*} || ! -w ${_optgenimg%/*} ) ]]; then
        die "Unable to write to '%s'" "$_optgenimg"
    fi
    msg "Starting build: '%s'" "$KERNELVERSION"
elif [[ -n "$_opttargetdir" ]]; then
    msg "Starting build: '%s'" "$KERNELVERSION"
else
    msg "Starting dry run: '%s'" "$KERNELVERSION"
fi
# set functrace and trap to catch errors in add_* functions
declare -i _builderrors=0
preload_builtin_modules
map run_build_hook "${_hooks[@]}" || (( ++_builderrors ))
install_modules "${!_modpaths[@]}"
# this is simply a nice-to-have -- it doesn't matter if it fails.
ldconfig -r "$BUILDROOT" &>/dev/null
# remove /var/cache/ldconfig/aux-cache for reproducability
rm -f -- "$BUILDROOT/var/cache/ldconfig/aux-cache"
# Set umask to create initramfs images as 600
umask 077
if [[ -n "$_optgenimg" ]]; then
    build_image "$_optgenimg" "${COMPRESSION}" || exit 1
elif [[ -n "$_opttargetdir" ]]; then
    msg "Build complete."
else
    msg "Dry run complete, use -g IMAGE to generate a real image"
fi
exit $(( !!_builderrors ))

# vim: set ft=sh ts=4 sw=4 et:
