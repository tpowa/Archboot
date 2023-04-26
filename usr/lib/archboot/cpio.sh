#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch Linux mkinitcpio - modular tool for building an initramfs image
# simplified, stripped down, optimized for size and speed
# by Tobias Powalowski <tpowa@archlinux.org>

# no long options support in archboot
parseopts() {
    local opt='' optarg='' i='' shortopts="$1"
    local -a unused_argv=()
    shift
    shift
    while (( $# )); do
        case "$1" in
            --) # explicit end of options
                shift
                break
                ;;
            -[!-]*) # short option
                for (( i = 1; i < ${#1}; i++ )); do
                    opt=${1:i:1}
                    # option doesn't exist
                    if [[ $shortopts != *$opt* ]]; then
                        printf "%s: invalid option -- '%s'\n" "${0##*/}" "$opt"
                        OPTRET=(--)
                        return 1
                    fi
                    OPTRET+=("-$opt")
                    # option requires optarg
                    if [[ "$shortopts" == *"${opt}:"* ]]; then
                        # if we're not at the end of the option chunk, the rest is the optarg
                        if (( i < ${#1} - 1 )); then
                            OPTRET+=("${1:i+1}")
                            break
                        # if we're at the end, grab the the next positional, if it exists
                        elif (( i == ${#1} - 1 )) && [[ -n "$2" ]]; then
                            OPTRET+=("$2")
                            shift
                            break
                        # parse failure
                        else
                            printf "%s: option '%s' requires an argument\n" "${0##*/}" "-$opt"
                            OPTRET=(--)
                            return 1
                        fi
                    fi
                done
                ;;
            *) # non-option arg encountered, add it as a parameter
                unused_argv+=("$1")
                ;;
        esac
        shift
    done
    # add end-of-opt terminator and any leftover positional parameters
    OPTRET+=('--' "${unused_argv[@]}" "$@")
    return 0
}

kver() {
    # this is intentionally very loose. only ensure that we're
    # dealing with some sort of string that starts with something
    # resembling dotted decimal notation. remember that there's no
    # requirement for CONFIG_LOCALVERSION to be set.
    local kver re='^[[:digit:]]+(\.[[:digit:]]+)+'
    local arch bytes reader
    arch="$(uname -m)"
    if [[ $arch == @(i?86|x86_64) ]]; then
        local -i offset
        offset="$(od -An -j0x20E -dN2 "$1")" || return
        read -r kver _ < \
            <(dd if="$1" bs=1 count=127 skip=$((offset + 0x200)) 2>/dev/null)
    else
        reader='cat'
        bytes="$(od -An -t x2 -N2 "$1" | tr -dc '[:alnum:]')"
        [[ "$bytes" == '8b1f' ]] && reader='zcat'
        read -r _ _ kver _ < <($reader "$1" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]+]+)+')
    fi
    [[ "$kver" =~ $re ]] || return 1
    printf '%s' "$kver"
}

msg() {
    local mesg="$1"; shift
    # shellcheck disable=SC2059
    printf "$_color_green==>$_color_none $_color_bold$mesg$_color_none\n" "$@" >&1
}

msg2() {
    local mesg="$1"; shift
    # shellcheck disable=SC2059
    printf "  $_color_blue->$_color_none $_color_bold$mesg$_color_none\n" "$@" >&1
}

warning() {
    local mesg="$1"; shift
    # shellcheck disable=SC2059
    printf "$_color_yellow==> WARNING:$_color_none $_color_bold$mesg$_color_none\n" "$@" >&2
}

error() {
    local mesg="$1"; shift
    # shellcheck disable=SC2059
    printf "$_color_red==> ERROR:$_color_none $_color_bold$mesg$_color_none\n" "$@" >&2
    return 1
}

die() {
    error "$@"
    cleanup 1
}

map() {
    local r=0
    for _ in "${@:2}"; do
        # shellcheck disable=SC1105,SC2210,SC2035
        "$1" "$_" || (( $# > 255 ? r=1 : ++r ))
    done
    return "$r"
}

modprobe() {
    # _optmoduleroot is assigned in mkinitcpio
    # shellcheck disable=SC2154
    command modprobe -d "$_optmoduleroot" -S "$KERNELVERSION" "$@"
}

all_modules() {
    # Add modules to the initcpio, filtered by grep.
    #   $@: filter arguments to grep
    #   -f FILTER: ERE to filter found modules
    local -i count=0
    local mod='' OPTIND='' OPTARG='' modfilter=()
    while getopts ':f:' flag; do
        [[ "$flag" = "f" ]] && modfilter+=("$OPTARG")
    done
    shift $(( OPTIND - 1 ))
    # _d_kmoduledir is assigned in mkinitcpio
    # shellcheck disable=SC2154
    while read -r -d '' mod; do
        (( ++count ))
        for f in "${modfilter[@]}"; do
            [[ "$mod" =~ $f ]] && continue 2
        done
        mod="${mod##*/}"
        mod="${mod%.ko*}"
        printf '%s\n' "${mod//-/_}"
    done < <(find "$_d_kmoduledir" -name '*.ko*' -print0 2>/dev/null | grep -EZz "$@")
    (( count ))
}

add_all_modules() {
    # Add modules to the initcpio.
    #   $@: arguments to all_modules
    local mod
    local -a mods
    mapfile -t mods < <(all_modules "$@")
    map add_module "${mods[@]}"
    return $(( !${#mods[*]} ))
}

add_firmware() {
    # add a firmware file to the image.
    #   $1: firmware path fragment
    local fw fwpath
    local -a fwfile
    local -i r=1
    fwpath=/lib/firmware
    for fw; do
        # shellcheck disable=SC2154
        if ! compgen -G "${BUILDROOT}${fwpath}/${fw}?(.*)" &>/dev/null; then
            if read -r fwfile < <(compgen -G "${fwpath}/${fw}?(.*)"); then
                map add_file "${fwfile[@]}"
                break
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
        fi
        if [[ -f "$sodep" && ! -e "${BUILDROOT}${sodep}" ]]; then
            add_file "$sodep" "$sodep"
        fi
    done <<< "$lddout"
    return 0
}

initialize_buildroot() {
    # creates a temporary directory for the buildroot and initialize it with a
    # basic set of necessary directories and symlinks
    local workdir='' kernver="$1" arch buildroot osreleasefile
    arch="$(uname -m)"
    if ! workdir="$(mktemp -d --tmpdir mkinitcpio.XXXXXX)"; then
        error 'Failed to create temporary working directory in %s' "${TMPDIR:-/tmp}"
        return 1
    fi
    buildroot="${2:-$workdir/root}"
    if [[ ! -w "${2:-$workdir}" ]]; then
        error 'Unable to write to build root: %s' "$buildroot"
        return 1
    fi
    # base directory structure
    install -dm755 "$buildroot"/{new_root,proc,sys,dev,run,tmp,var,etc,usr/{local{,/bin,/sbin,/lib},lib,bin}}
    ln -s "usr/lib" "$buildroot/lib"
    ln -s "bin"     "$buildroot/usr/sbin"
    ln -s "usr/bin" "$buildroot/bin"
    ln -s "usr/bin" "$buildroot/sbin"
    ln -s "/run"    "$buildroot/var/run"
    case "$arch" in
        x86_64)
            ln -s "lib"     "$buildroot/usr/lib64"
            ln -s "usr/lib" "$buildroot/lib64"
            ;;
    esac
    # kernel module dir
    [[ "$kernver" != 'none' ]] && install -dm755 "$buildroot/usr/lib/modules/$kernver/kernel"
    # mount tables
    ln -s ../proc/self/mounts "$buildroot/etc/mtab"
    : >"$buildroot/etc/fstab"
    # add os-release for systemd
    if [[ -e /etc/os-release ]]; then
        if [[ -L /etc/os-release ]]; then
            osreleasefile="$(realpath -- /etc/os-release)"
            install -Dm0644 "$osreleasefile" "${buildroot}${osreleasefile}"
            cp -adT /etc/os-release "${buildroot}/etc/os-release"
        else
            install -Dm0644 /etc/os-release "${buildroot}/etc/os-release"
        fi
    fi
    # add a blank ld.so.conf to keep ldconfig happy
    : >"$buildroot/etc/ld.so.conf"
    printf '%s' "$workdir"
}

run_build_hook() {
    local hook="$1" script='' resolved=''
    # shellcheck disable=SC2034
    local MODULES=() BINARIES=() FILES=() SCRIPT=''
    # find script in install dirs
    # _d_install is assigned in mkinitcpio
    # shellcheck disable=SC2154
    if ! script="$(PATH="$_d_install" type -P "$hook")"; then
        error "Hook '$hook' cannot be found"
        return 1
    fi
    # source
    unset -f build
    # shellcheck disable=SC1090
    if ! . "$script"; then
        error 'Failed to read %s' "$script"
        return 1
    fi
    if ! declare -f build >/dev/null; then
        error "Hook '%s' has no build function" "${script}"
        return 1
    fi
    # run
    msg2 "Running build hook: [%s]" "${script##*/}"
    build
    # if we made it this far, return successfully. Hooks can
    # do their own error catching if it's severe enough, and
    # we already capture errors from the add_* functions.
    return 0
}

try_enable_color() {
    local colors
    if ! colors="$(tput colors 2>/dev/null)"; then
        warning "Failed to enable color. Check your TERM environment variable"
        return
    fi
    if (( colors > 0 )) && tput setaf 0 &>/dev/null; then
        _color_none="$(tput sgr0)"
        _color_bold="$(tput bold)"
        _color_blue="$_color_bold$(tput setaf 4)"
        _color_green="$_color_bold$(tput setaf 2)"
        _color_red="$_color_bold$(tput setaf 1)"
        _color_yellow="$_color_bold$(tput setaf 3)"
    fi
}

install_modules() {
    command tar --hard-dereference -C / -cpf - "$@" | tar -C "${BUILDROOT}" -xpf -
    msg "Generating module dependencies"
    map add_file "$_d_kmoduledir"/modules.{builtin,builtin.modinfo,order}
    depmod -b "$BUILDROOT" "$KERNELVERSION"
    # remove all non-binary module.* files (except devname for on-demand module loading)
    rm "${BUILDROOT}${_d_kmoduledir}"/modules.!(*.bin|devname|softdep)
}
