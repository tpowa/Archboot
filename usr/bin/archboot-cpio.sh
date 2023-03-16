#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# archbootcpio simplified and stripped down
# Arch Linux mkinitcpio - modular tool for building an initramfs images
# optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

shopt -s extglob

### globals within mkinitcpio, but not intended to be used by hooks

# needed files/directories
_f_functions=/usr/lib/initcpio/functions
_f_config=
_d_hooks=/lib/initcpio/hooks
_d_install=/lib/initcpio/install
_d_flag_hooks=
_d_flag_install=

# options and runtime data
_optmoduleroot='' _optgenimg=''
_optcompress='' _opttargetdir=''
_optosrelease=''
_optsavetree=0
_optquiet=1 _optcolor=1
_optaddhooks=() _hooks=()  _tmpfiles=()
declare -A _runhooks _addedmodules _modpaths _autodetect_cache

# Sanitize environment further
# GREP_OPTIONS="--color=always" will break everything
# CDPATH can affect cd and pushd
# LIBMOUNT_* options can affect findmnt and other tools
unset GREP_OPTIONS CDPATH "${!LIBMOUNT_@}"

usage() {
    cat <<EOF
usage: ${0##*/} [options]

  Options:
   -A, --addhooks <hooks>       Add specified hooks, comma separated, to image
   -c, --config <config>        Use config file
   -g, --generate <path>        Generate cpio image and write to specified path
   -h, --help                   Display this message and exit
   -k, --kernel <kernelver>     Use specified kernel version (default: $(uname -r))
   -r, --moduleroot <dir>       Root directory for modules (default: /)
   -s, --save                   Save build directory. (default: no)
   -d, --generatedir <dir>      Write generated image into <dir>
   -t, --builddir <dir>         Use DIR as the temporary build directory
   -D, --hookdir <dir>          Specify where to look for hooks
   -z, --compress <program>     Use an alternate compressor on the image (cat, xz, lz4, zstd)
EOF
}

# The function is called from the EXIT trap
# shellcheck disable=SC2317
cleanup() {
    local err="${1:-$?}"

    if (( ${#_tmpfiles[@]} )); then
        rm -f -- "${_tmpfiles[@]}"
    fi
    if [[ -n "$_d_workdir" ]]; then
        # when _optpreset is set, we're in the main loop, not a worker process
        if (( _optsavetree )) && [[ -z ${_optpreset[*]} ]]; then
            printf '%s\n' "${!_autodetect_cache[@]}" > "$_d_workdir/autodetect_modules"
            msg "build directory saved in '%s'" "$_d_workdir"
        else
            rm -rf -- "$_d_workdir"
        fi
    fi

    exit "$err"
}

resolve_kernver() {
    local kernel="$1" arch=''

    if [[ -z "$kernel" ]]; then
        uname -r
        return 0
    fi

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

    arch="$(uname -m)"
    if [[ "$arch" != @(i?86|x86_64) ]]; then
        error "kernel version extraction from image not supported for '%s' architecture" "$arch"
        error "there's a chance the generic version extractor may work with a valid uncompressed kernel image"
    fi

    return 1
}

compute_hookset() {
    local h

    for h in "${HOOKS[@]}" "${_optaddhooks[@]}"; do
        _hooks+=("$h")
    done
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
    find . -mindepth 1 |
        cpio --reproducible --quiet -o -H newc |
            $compress "${COMPRESSION_OPTIONS[@]}" > "$compressout"

    pipestatus=("${PIPESTATUS[@]}")
    pipeprogs=('find' 'cpio' "$compress")

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

process_preset() (

    . "$1" || die "Failed to load preset: \`%s'" "$1"

    (( ! ${#PRESETS[@]} )) && warning "Preset file \`%s' is empty or does not contain any presets." "$1"
    exit 0
)

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

# shellcheck source=functions
. "$_f_functions"

### overwriting functions
add_firmware() {
    # add a firmware file to the image.
    #   $1: firmware path fragment

    local fw fwpath fwfile
    fwpath=/lib/firmware

    for fw; do
        # shellcheck disable=SC2154
        if ! compgen -G "${BUILDROOT}${fwpath}/${fw}"?(.*) &>/dev/null; then
            if fwfile="$(compgen -G "${fwpath}/${fw}"?(.*))"; then
                add_file "$fwfile"
            fi
        fi
    done
    return 0
}

add_module() {
    # Add a kernel module to the initcpio image. Dependencies will be
    # discovered and added.
    #   $1: module name

    local target='' module='' softdeps=() deps=() field='' value='' firmware=()

    if [[ "$1" == *\? ]]; then
        set -- "${1%?}"
    fi

    target="${1%.ko*}" target="${target//-/_}"

    # skip expensive stuff if this module has already been added
    (( _addedmodules["$target"] == 1 )) && return

    while IFS=':= ' read -r -d '' field value; do
        case "$field" in
            filename)
                # Only add modules with filenames that look like paths (e.g.
                # it might be reported as "(builtin)"). We'll defer actually
                # checking whether or not the file exists -- any errors can be
                # handled during module install time.
                if [[ "$value" == /* ]]; then
                    module="${value##*/}" module="${module%.ko*}"
                    _modpaths[".$value"]=1
                    _addedmodules["${module//-/_}"]=1
                fi
                ;;
            depends)
                IFS=',' read -r -a deps <<< "$value"
                map add_module "${deps[@]}"
                ;;
            firmware)
                firmware+=("$value")
                ;;
            softdep)
                read -ra softdeps <<<"$value"
                for module in "${softdeps[@]}"; do
                    [[ $module == *: ]] && continue
                    add_module "$module?"
                done
                ;;
        esac
    done < <(modinfo -b "$_optmoduleroot" -k "$KERNELVERSION" -0 "$target" 2>/dev/null)

    if (( ${#firmware[*]} )); then
        add_firmware "${firmware[@]}"
    fi
}

add_checked_modules() {
    # Add modules to the initcpio, filtered by the list of autodetected
    # modules.
    #   $@: arguments to all_modules

    local mods

    mapfile -t mods < <(all_modules "$@")

    map add_module "${mods[@]}"

    return $(( !${#mods[*]} ))
}

add_full_dir() {
    # Add a directory and all its contents, recursively, to the initcpio image.
    # No parsing is performed and the contents of the directory is added as is.
    #   $1: path to directory
    if [[ -n $1 && -d $1 ]]; then
        command tar -C /  --hard-dereference -cpf - ."$1" | tar -C "${BUILDROOT}" -xpf - || return 1
    fi
}

add_dir() {
    # add a directory (with parents) to $BUILDROOT
    #   $1: pathname on initcpio
    #   $2: mode (optional)
    local mode="${2:-755}"

    # shellcheck disable=SC2153
    if [[ -d "${BUILDROOT}${1}" ]]; then
        # ignore dir already exists
        return 0
    fi

    command mkdir -p -m "${mode}" "${BUILDROOT}${1}" || return 1
}

add_symlink() {
    # Add a symlink to the initcpio image. There is no checking done
    # to ensure that the target of the symlink exists.
    #   $1: pathname of symlink on image
    #   $2: absolute path to target of symlink (optional, can be read from $1)

    local name="$1" target="${2:-$1}" linkobject

    # find out the link target
    if [[ "$name" == "$target" ]]; then
        linkobject="$(find "$target" -prune -printf '%l')"
        # use relative path if the target is a file in the same directory as the link
        # anything more would lead to the insanity of parsing each element in its path
        if [[ "$linkobject" != *'/'* && ! -L "${name%/*}/${linkobject}" ]]; then
            target="$linkobject"
        else
            target="$(realpath -eq -- "$target")"
        fi
    elif [[ -L "$target" ]]; then
        target="$(realpath -eq -- "$target")"
    fi

    add_dir "${name%/*}"
    ln -sfn "$target" "${BUILDROOT}${name}"
}

add_file() {
    # Add a plain file to the initcpio image. No parsing is performed and only
    # the singular file is added.
    #   $1: path to file
    #   $2: destination on initcpio (optional, defaults to same as source)
    #   $3: mode

    # determine source and destination
    local src="$1" dest="${2:-$1}" mode="$3" srcrealpath

    if [[ ! -e "${BUILDROOT}${dest}" ]]; then
        if [[ "$src" != "$dest" ]]; then
            command tar --hard-dereference --transform="s|$src|$dest|" -C / -cpf - ."$src" | tar -C "${BUILDROOT}" -xpf - || return 1
        else
            command tar --hard-dereference -C / -cpf - ."$src" | tar -C "${BUILDROOT}" -xpf - || return 1
        fi
        if [[ -L "$src" ]]; then
            srcrealpath="$(realpath -- "$src")"
            add_file  "$srcrealpath" "$srcrealpath" "$mode"
        else
            if [[ -n $mode ]]; then
                command chmod "$mode" ${BUILDROOT}${dest}
            fi
        fi
    fi
}

add_binary() {
    # Add a binary file to the initcpio image. library dependencies will
    # be discovered and added.
    #   $1: path to binary
    #   $2: destination on initcpio (optional, defaults to same as source)

    local line='' regex='' binary='' dest='' mode='' sodep=''

    if [[ "${1:0:1}" != '/' ]]; then
        binary="$(type -P "$1")"
    else
        binary="$1"
    fi

    dest="${2:-$binary}"

    add_file "$binary" "$dest"

    # non-binaries
    if ! lddout="$(ldd "$binary" 2>/dev/null)"; then
        return 0
    fi
    # resolve sodeps
    regex='^(|.+ )(/.+) \(0x[a-fA-F0-9]+\)'
    while read -r line; do
        if [[ "$line" =~ $regex ]]; then
            sodep="${BASH_REMATCH[2]}"
        elif [[ "$line" = *'not found' ]]; then
            error "binary dependency '%s' not found for '%s'" "${line%% *}" "$1"
            (( ++_builderrors ))
            continue
        fi

        if [[ -f "$sodep" && ! -e "${BUILDROOT}${sodep}" ]]; then
            add_file "$sodep" "$sodep"
        fi
    done <<< "$lddout"

    return 0
}

install_modules() {

    command tar --hard-dereference -C / -cpf - "$@" | tar -C "${BUILDROOT}" -xpf -

    msg "Generating module dependencies"
    map add_file "$_d_kmoduledir"/modules.{builtin,builtin.modinfo,order}
    depmod -b "$BUILDROOT" "$KERNELVERSION"

    # remove all non-binary module.* files (except devname for on-demand module loading)
    rm "${BUILDROOT}${_d_kmoduledir}"/modules.!(*.bin|devname|softdep)
}

trap 'cleanup' EXIT

_opt_short='A:c:D:g:H:hk:nLMPp:Rr:S:sd:t:U:Vvz:'
_opt_long=('add:' 'addhooks:' 'config:' 'generate:' 'hookdir': 'help'
          'kernel:' 'listhooks' 'moduleroot:' 'nocolor'
          'save' 'generatedir:' 'builddir:' 'compress:'
          'osrelease:')

parseopts "$_opt_short" "${_opt_long[@]}" -- "$@" || exit 1
set -- "${OPTRET[@]}"
unset _opt_short _opt_long OPTRET

if [[ -z "$1" ]]; then
    usage
    cleanup 0
fi

while :; do
    case "$1" in
        # --add remains for backwards compat
        -A|--add|--addhooks)
            shift
            IFS=, read -r -a add <<< "$1"
            _optaddhooks+=("${add[@]}")
            unset add
            ;;
        -c|--config)
            shift
            _f_config="$1"
            ;;
        -k|--kernel)
            shift
            KERNELVERSION="$1"
            ;;
        -s|--save)
            _optsavetree=1
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
        -t|--builddir)
            shift
            export TMPDIR="$1"
            ;;
        -z|--compress)
            shift
            _optcompress="$1"
            ;;
        -r|--moduleroot)
            shift
            _optmoduleroot="$1"
            ;;
        -D|--hookdir)
            shift
            _d_flag_hooks+="$1/hooks:"
            _d_flag_install+="$1/install:"
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

if [[ -n "$_d_flag_hooks" && -n "$_d_flag_install" ]]; then
    _d_hooks="${_d_flag_hooks%:}"
    _d_install="${_d_flag_install%:}"
fi

# insist that /proc and /dev be mounted (important for chroots)
# NOTE: avoid using mountpoint for this -- look for the paths that we actually
# use in mkinitcpio. Avoids issues like FS#26344.
[[ -e /proc/self/mountinfo ]] || die "/proc must be mounted!"
[[ -e /dev/fd ]] || die "/dev must be mounted!"

# use preset $_optpreset (exits after processing)
if (( ${#_optpreset[*]} )); then
    map process_preset "${_optpreset[@]}"
    exit
fi

if [[ "$KERNELVERSION" != 'none' ]]; then
    KERNELVERSION="$(resolve_kernver "$KERNELVERSION")" || exit 1
    _d_kmoduledir="$_optmoduleroot/lib/modules/$KERNELVERSION"
    [[ -d "$_d_kmoduledir" ]] || die "'$_d_kmoduledir' is not a valid kernel module directory"
fi

_d_workdir="$(initialize_buildroot "$KERNELVERSION" "$_opttargetdir")" || exit 1
BUILDROOT="${_opttargetdir:-$_d_workdir/root}"

# shellcheck source=mkinitcpio.conf
! . "$_f_config" 2>/dev/null && die "Failed to read configuration '%s'" "$_f_config"

arrayize_config

# after returning, hooks are populated into the array '_hooks'
# HOOKS should not be referenced from here on
compute_hookset

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

    _optcompress="${_optcompress:-"${COMPRESSION:-zstd}"}"
    if ! type -P "$_optcompress" >/dev/null; then
        warning "Unable to locate compression method: '%s'" "$_optcompress"
        _optcompress='cat'
    fi

    msg "Starting build: '%s'" "$KERNELVERSION"
elif [[ -n "$_opttargetdir" ]]; then
    msg "Starting build: '%s'" "$KERNELVERSION"
else
    msg "Starting dry run: '%s'" "$KERNELVERSION"
fi

# set functrace and trap to catch errors in add_* functions
declare -i _builderrors=0
set -o functrace
trap '(( $? )) && [[ "$FUNCNAME" == add_* ]] && (( ++_builderrors ))' RETURN

preload_builtin_modules

map run_build_hook "${_hooks[@]}" || (( ++_builderrors ))

# process config file
parse_config "$_f_config"

# switch out the error handler to catch all errors
trap -- RETURN
trap '(( ++_builderrors ))' ERR
set -o errtrace

install_modules "${!_modpaths[@]}"

# unset errtrace and trap
set +o functrace
set +o errtrace
trap -- ERR

# this is simply a nice-to-have -- it doesn't matter if it fails.
ldconfig -r "$BUILDROOT" &>/dev/null
# remove /var/cache/ldconfig/aux-cache for reproducability
rm -f -- "$BUILDROOT/var/cache/ldconfig/aux-cache"

# Set umask to create initramfs images and unified kernel images as 600
umask 077

if [[ -n "$_optgenimg" ]]; then
    build_image "$_optgenimg" "$_optcompress" || exit 1
elif [[ -n "$_opttargetdir" ]]; then
    msg "Build complete."
else
    msg "Dry run complete, use -g IMAGE to generate a real image"
fi

exit $(( !!_builderrors ))

# vim: set ft=sh ts=4 sw=4 et:
