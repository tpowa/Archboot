#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create Container\e[m"
    echo -e "\e[1m---------------------------\e[m"
    echo "This will create an Archboot container for an Archboot image."
    echo
    echo "Options:"
    echo -e " \e[1m-cc\e[m    Cleanup container eg. removing manpages, includes..."
    echo -e " \e[1m-cp\e[m    Cleanup container package cache"
    echo -e " \e[1m-install-source=<server>\e[m    Use <server> containing Archboot repository"
    echo
    echo -e "Usage: \e[1m${_BASENAME} <directory> <options>\e[m"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -cc|--cc) _CLEANUP_CONTAINER="1" ;;
            -cp|--cp) _CLEANUP_CACHE="1" ;;
            -install-source=*|--install-source=*) _INSTALL_SOURCE="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
        esac
        shift
    done
}

_clean_cache() {
    if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
        echo "Cleaning pacman cache in ${1}..."
        rm -r "${1}${_CACHEDIR}"
    fi
    if rg -qw 'archboot' /etc/hostname; then
        echo "Cleaning Archboot ${_CACHEDIR}..."
        for i in "${1}${_CACHEDIR}"/*; do
            [[ "${i}" == "${1}${_LOCAL_DB}" ]] || rm -f "${_CACHEDIR}"/"$(basename "${i}")"
        done
    fi
}

_pacman_container() {
    if ! [[ -f ${3} && -f ${3}.sig ]]; then
        echo "Downloading ${3}..."
        ${_DLPROG} -O "${2}"/"${3}"
        ${_DLPROG} -O "${2}"/"${3}".sig
    else
        echo "Using local ${3}..."
    fi
    echo "Verifying ${3}..."
    gpg --verify "${3}.sig" &>"${_NO_LOG}" || exit 1
    bsdtar -C "${1}" -xf "${3}"
    echo "Updating container to latest packages..."
    ${_NSPAWN} "${1}" pacman -Syu --noconfirm &>"${_NO_LOG}"
}

# clean container from not needed files
_clean_container() {
    if [[ "${_CLEANUP_CONTAINER}" ==  "1" ]]; then
        echo "Cleaning container, delete not needed files from ${1}..."
        rm -r "${1}"/usr/include
        rm -r "${1}"/usr/share/{aclocal,applications,audit-rules,awk,common-lisp,emacs,et,fish,gettext,gettext-[0-9]*,glib-[0-9]*,gnupg,gtk-doc,iana-etc,icons,icu,keyutils,libalpm,libgpg-error,makepkg-template,misc,pixmaps,pkgconfig,screen,smartmontools,ss,tabset,vala,xml,man,info}
        rm -r "${1}"/usr/lib/{audit,awk,binfmt.d,cmake,dracut,e2fsprogs,environment.d,gawk,getconf,gettext,glib-[0-9]*,gnupg,gssproxy,icu,krb5,ldscripts,libnl,pkgconfig,siconv,tar,xfsprogs}
        # locale cleaning
        fd -u --min-depth 2 -E '/be/' -E '/bg/' \
             -E '/cs/' -E '/da/' -E '/de/' -E '/en/' \
             -E '/el/' -E '/es/' -E '/fi/' -E '/fr/' \
             -E '/hu/' -E '/it/' -E '/lt/' -E '/lv/' \
             -E '/mk/' -E '/nl/' -E '/nn/' -E '/pl/' \
             -E '/pt/' -E '/ro/' -E '/ru/' -E '/sk/' \
             -E '/sr/' -E '/sv/' -E '/tr/' -E '/uk/' \
             . "${1}"/usr/share/locale/ -X rm &>"${_NO_LOG}"
        fd -u -t f -E 'UTF-8.gz' . "${1}"/usr/share/i18n/charmaps -X rm &>"${_NO_LOG}"
        # not needed firmware files
        rm -r "${1}"/lib/firmware/{3com,acenic,advansys,agere_*,adaptec,airoha,amdtee,amlogic,amphion,ar3k,ar5523*,ar70*,ar9[0-9]*,arm,as102*,\
ath3k*,atmel,atusb,av7110,brcm,cadence,carl*,cavium,cirrus,cis,cpia2,cnm,cs42l43*,ct*,cxgb*,cmmb*,cypress,dabusb,dpaa2,dsp56k,dvb*,e100,\
edgeport,emi26,emi62,ene-ub6250,ess,f2255usb*,go7007,hfi1*,INT*,imx,inside-secure,isci,isdbt*,intel,ixp4xx,kaweth,keyspan*,\
korg,lbtf*,lgs8g75*,lt9611uxc*,matrox,meson,microchip,moxa,mrvl/prestera,mts*,myri10ge*,myricom,nxp,ositech,phanfw*,powervr,qat*,\
qca,r128,r8a*,realtek,rockchip,rp2*,rtl_bt,rsi*,sb16,s2250*,s5p-*,sdd_*,slicoss,sms1*,sun,sxg,tdmb*,ttusb-budget,ueagle-atm,usbdux*,\
TAS*,TIAS*,tehuti,ti,ti_*,ti-keystone,tlg2300*,tsse_*,v4l*,vicam,vntw*,vxge,wsm_*,wfx,whiteheat*,yam,yamaha}
    fi
}

_prepare_pacman() {
    # prepare pacman dirs
    echo "Creating directory in ${1}..."
    mkdir -p "${1}${_PACMAN_LIB}"
    for i in dev proc sys; do
    [[ -e "${1}/${i}" ]] || mkdir -m 555 "${1}/${i}"
    done
    # mount special filesystems to ${1}
    echo "Mounting special filesystems in ${1}..."
    mount proc "${1}/proc" -t proc -o nosuid,noexec,nodev
    mount sys "${1}/sys" -t sysfs -o nosuid,noexec,nodev,ro
    mount udev "${1}/dev" -t devtmpfs -o mode=0755,nosuid
    mount devpts "${1}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm "${1}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    echo "Removing Archboot repository sync db..."
    rm -f "${_PACMAN_LIB}"/sync/archboot.db
    echo "Updating Arch Linux keyring..."
    #shellcheck disable=SC2086,SC2068
    pacman -Sy --config ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING[@]} &>"${_NO_LOG}"
}

#shellcheck disable=SC2120
_create_pacman_conf() {
    if [[ -z "${_INSTALL_SOURCE}" ]]; then
        echo "Using default pacman.conf..."
        if [[ "${2}" == "use_binfmt" ]]; then
            _PACMAN_CONF="${1}${_PACMAN_CONF}"
            # CDN on aarch64 is broken sometimes
            # shellcheck disable=SC2016
            sd '^Server = http://mirror.archlinuxarm.org/$arch/$repo' \
               '# Server = http://mirror.archlinuxarm.org/$arch/$repo' "${1}"/etc/pacman.d/mirrorlist
            # shellcheck disable=SC2016
            sd '# Server = http://de3.mirror.archlinuxarm.org/$arch/$repo' \
               'Server = http://de3.mirror.archlinuxarm.org/$arch/$repo' "${1}"/etc/pacman.d/mirrorlist
        fi
        if ! rg -qw "\[archboot\]" "${_PACMAN_CONF}"; then
            echo "Adding Archboot repository to ${_PACMAN_CONF}..."
            echo "[archboot]" >> "${_PACMAN_CONF}"
            echo "Server = https://pkg.archboot.com" >> "${_PACMAN_CONF}"
        fi
        #shellcheck disable=SC2001
        [[ "${2}" == "use_binfmt" ]] && _PACMAN_CONF="$(echo "${_PACMAN_CONF}" | sd "^${1}" '')"
    else
        echo "Using custom pacman.conf..."
        _PACMAN_CONF="$(mktemp "${1}"/pacman.conf.XXX)"
        #shellcheck disable=SC2129
        echo "[options]" >> "${_PACMAN_CONF}"
        echo "Architecture = auto" >> "${_PACMAN_CONF}"
        echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
        echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
        echo "ParallelDownloads = 5" >> "${_PACMAN_CONF}"
        echo "Color" >> "${_PACMAN_CONF}"
        echo "[archboot]" >> "${_PACMAN_CONF}"
        echo "Server = ${_INSTALL_SOURCE}" >> "${_PACMAN_CONF}"
        [[ "${2}" == "use_binfmt" ]] && _PACMAN_CONF="$(basename "${_PACMAN_CONF}")"
    fi
}

_ssh_keys() {
    mkdir "${1}"/ssh-keys
    if [[ -f '/etc/archboot/ssh/archboot-key.pub' ]]; then
        echo "Using custom OpenSSH Key..."
        cp /etc/archboot/ssh/archboot-key.pub "${1}"/etc/archboot/ssh/
    else
        # don't run on local image
        if ! [[ -f "${_LOCAL_DB}" ]]; then
            echo "Generating new Archboot OpenSSH Key..."
            ssh-keygen -C Archboot -f "${1}"/etc/archboot/ssh/archboot-key -N 'Archboot' -q
        fi
    fi
}

_change_pacman_conf() {
    # enable pacman color support
    sd '^#Color' 'Color' "${1}"/etc/pacman.conf
}

# umount special filesystems
_umount_special() {
    echo "Unmounting special filesystems in ${1}..."
    umount -R "${1}"/{proc,sys,dev}
}

_install_base_packages() {
    if [[ "${_ARCH}" == "aarch64" ]]; then
        _MKINITCPIO="mkinitcpio=99"
    else
        _MKINITCPIO=initramfs
    fi
    if [[ "${2}" == "use_binfmt" ]]; then
        #shellcheck disable=SC2068
        echo "Downloading ${_KEYRING[*]} ${_PACKAGES[*]} to ${1}..."
        if rg -qw 'archboot' /etc/hostname; then
            #shellcheck disable=SC2086,SC2068
            ${_PACMAN} -Syw ${_KEYRING[@]} ${_PACKAGES[@]} ${_PACMAN_DEFAULTS} \
                        ${_PACMAN_DB} &>"${_LOG}" || exit 1
        else
            #shellcheck disable=SC2086,SC2068
            ${_PACMAN} -Syw ${_KEYRING[@]} ${_PACKAGES[@]} ${_PACMAN_DEFAULTS} \
                       ${_PACMAN_DB} &>"${_NO_LOG}" || exit 1
        fi
    fi
    #shellcheck disable=SC2068
    echo "Installing ${_KEYRING[*]} ${_PACKAGES[*]} to ${1}..."
    if rg -qw 'archboot' /etc/hostname; then
        #shellcheck disable=SC2086,SC2068
        ${_PACMAN} -Sy --assume-installed ${_MKINITCPIO} ${_KEYRING[@]} ${_PACKAGES[@]} \
                   ${_PACMAN_DEFAULTS} &>"${_LOG}" || exit 1
        echo "Downloading mkinitcpio to ${1}..."
        #shellcheck disable=SC2086
        ${_PACMAN} -Syw mkinitcpio ${_PACMAN_DEFAULTS} >"${_LOG}" 2>&1 || exit 1
    else
        #shellcheck disable=SC2086,SC2068
        ${_PACMAN} -Sy --assume-installed ${_MKINITCPIO} ${_KEYRING[@]} ${_PACKAGES[@]} \
                   ${_PACMAN_DEFAULTS} &>"${_NO_LOG}" || exit 1
        echo "Downloading mkinitcpio to ${1}..."
        #shellcheck disable=SC2086
        ${_PACMAN} -Syw mkinitcpio ${_PACMAN_DEFAULTS} >"${_NO_LOG}" 2>&1 || exit 1
    fi
}

_install_archboot() {
    if [[ "${2}" == "use_binfmt" ]]; then
        _pacman_key "${1}"
    else
        _pacman_key_system
    fi
    echo "Installing ${_ARCHBOOT} to ${1}..."
    if rg -qw 'archboot' /etc/hostname; then
        #shellcheck disable=SC2086
        ${_PACMAN} -Sy ${_ARCHBOOT} ${_PACMAN_DEFAULTS} &>"${_LOG}" || exit 1
        echo "Downloading ${_MAN_INFO_PACKAGES[*]} to ${1}..."
        #shellcheck disable=SC2086,SC2068
        ${_PACMAN} -Syw ${_MAN_INFO_PACKAGES[@]} ${_PACMAN_DEFAULTS} \
                   ${_PACMAN_DB} &>"${_LOG}" || exit 1
    else
        #shellcheck disable=SC2086
        ${_PACMAN} -Sy ${_ARCHBOOT} ${_PACMAN_DEFAULTS} &>"${_NO_LOG}" || exit 1
        echo "Downloading ${_MAN_INFO_PACKAGES[*]} to ${1}..."
        #shellcheck disable=SC2086,SC2068
        ${_PACMAN} -Syw ${_MAN_INFO_PACKAGES[@]} ${_PACMAN_DEFAULTS} \
                   ${_PACMAN_DB} &>"${_NO_LOG}" || exit 1
    fi
    # cleanup
    if ! [[ "${2}"  == "use_binfmt" ]]; then
        rm -r "${1}"/blankdb
        echo "Removing Archboot repository sync db..."
        rm "${_PACMAN_LIB}"/sync/archboot.db
    fi
}

_copy_mirrorlist_and_pacman_conf() {
    # copy local mirrorlist to container
    echo "Creating pacman config and mirrorlist in container..."
    cp "/etc/pacman.d/mirrorlist" "${1}/etc/pacman.d/mirrorlist"
    # only copy from Archboot pacman.conf, else use default file
    rg -qw 'archboot' /etc/hostname && cp /etc/pacman.conf "${1}"/etc/pacman.conf
}

_copy_archboot_defaults() {
    echo "Copying Archboot defaults to container..."
    cp /etc/archboot/defaults "${1}"/etc/archboot/defaults
}

_container_reproducibility() {
    echo "Reproducibility changes..."
    #shellcheck disable=SC2016
    sd '(INSTALLDATE%)\n.*' '$1\n0' "${1}""${_PACMAN_LIB}"/local/*/desc
    rm "${1}"/var/cache/ldconfig/aux-cache
    rm "${1}"/etc/ssl/certs/java/cacerts
}

_set_hostname() {
    echo "Setting hostname to archboot..."
    echo 'archboot' > "${1}/etc/hostname"
}

_depmod() {
    echo "Running depmod..."
    _KERNELVERSION="$(basename "${1}"/lib/modules/*)"
    ${_NSPAWN} "${1}" depmod "${_KERNELVERSION}"
}

