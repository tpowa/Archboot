#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_CACHEDIR="${1}/var/cache/pacman/pkg"

_usage () {
    echo "CREATE ARCHBOOT CONTAINER"
    echo "-----------------------------"
    echo "This will create an archboot container for an archboot image."
    echo "Usage: ${_BASENAME} <directory> <options>"
    echo " Options:"
    echo "  -cc    Cleanup container eg. remove manpages, includes ..."
    echo "  -cp    Cleanup container package cache"
    echo "  -install-source=Server add package server with archboot repository"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -cc|--cc) _CLEANUP_CONTAINER="1" ;;
            -cp|--cp) _CLEANUP_CACHE="1" ;;
            -install-source=*|--install-source=*) _INSTALL_SOURCE="$(echo "${1}" | awk -F= '{print $2;}')" ;;
        esac
        shift
    done
}

_clean_cache() {
    if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
        echo "Clean pacman cache in ${1} ..."
        rm -r "${1}"/var/cache/pacman
    fi
}

_aarch64_pacman_chroot() {
    if ! [[ -f ${_PACMAN_AARCH64_CHROOT} && -f ${_PACMAN_AARCH64_CHROOT}.sig ]]; then
        echo "Downloading ${_PACMAN_AARCH64_CHROOT} ..."
        wget ${_ARCHBOOT_AARCH64_CHROOT_PUBLIC}/${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
    else
        echo "Using local ${_PACMAN_AARCH64_CHROOT} ..."
    fi
    echo "Verifying ${_PACMAN_AARCH64_CHROOT} ..."
    gpg --verify "${_PACMAN_AARCH64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${1}" -xf "${_PACMAN_AARCH64_CHROOT}"
    if [[ -f ${_PACMAN_AARCH64_CHROOT} && -f ${_PACMAN_AARCH64_CHROOT}.sig ]]; then
        echo "Removing installation tarball ${_PACMAN_AARCH64_CHROOT} ..."
        rm ${_PACMAN_AARCH64_CHROOT}{,.sig}
    fi
    echo "Update container to latest packages..."
    systemd-nspawn -D "${1}" pacman -Syu --noconfirm >/dev/null 2>&1
}
    
# clean container from not needed files
_clean_container() {
    if [[ "${_CLEANUP_CONTAINER}" ==  "1" ]]; then
        echo "Clean container, delete not needed files from ${1} ..."
        rm -r "${1}"/usr/include
        rm -r "${1}"/usr/share/{aclocal,applications,audit,avahi,awk,bash-completion,cmake,common-lisp,cracklib,dhclient,dhcpcd,dict,dnsmasq,emacs,et,fish,gdb,gettext,gettext-0.21,glib-2.0,gnupg,graphite2,gtk-doc,iana-etc,icons,icu,iptables,keyutils,libalpm,libgpg-error,makepkg-template,misc,mkinitcpio,ncat,ntp,p11-kit,pixmaps,pkgconfig,readline,screen,smartmontools,ss,stoken,tabset,texinfo,vala,xml,xtables,zoneinfo-leaps,man,doc,info,perl5,i18n,locale}
        rm -r "${1}"/usr/lib/{audit,avahi,awk,bash,binfmt.d,cifs-utils,cmake,coreutils,cryptsetup,cups,dracut,e2fsprogs,engines-1.1,environment.d,gawk,getconf,gettext,girepository-1.0,glib-2.0,gnupg,gssproxy,guile,icu,itcl4.2.2,iwd,krb5,ldb,ldscripts,libnl,libproxy,ntfs-3g,openconnect,openssl-1.0,p11-kit,pcsc,perl5,pkcs11,pkgconfig,python3.10,rsync,samba,sasl2,siconv,sysctl.d,sysusers.d,tar,tcl8.6,tcl8,tdbc1.1.3,tdbcmysql1.1.3,tdbcodbc1.1.3,tdbcpostgres1.1.3,terminfo,texinfo,thread2.8.7,valgrind,xfsprogs,xplc-0.3.13,xtables}
    fi
}

# remove mkinitcpio hooks to speed up process, remove not needed initramdisks
_clean_mkinitcpio() {
    echo "Clean mkinitcpio from ${1} ..."
    [[ -e "${1}/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook" ]] && rm "${1}/usr/share/libalpm/hooks/60-mkinitcpio-remove.hook"
    [[ -e "${1}/usr/share/libalpm/hooks/90-mkinitcpio-install.hook" ]] && rm "${1}/usr/share/libalpm/hooks/90-mkinitcpio-install.hook"
    [[ -e "${1}/boot/initramfs-linux.img" ]] && rm "${1}/boot/initramfs-linux.img"
    [[ -e "${1}/boot/initramfs-linux-fallback.img" ]] && rm "${1}/boot/initramfs-linux-fallback.img"
}

# Clean cache on archboot environment
_clean_archboot_cache() {
    grep -qw 'archboot' /etc/hostname && (echo "Cleaning archboot /var/cache/pacman/pkg ..."; rm -r /var/cache/pacman/pkg)
}

_prepare_pacman() {
    # prepare pacman dirs
    echo "Create directories in ${1} ..."
    mkdir -p "${1}/var/lib/pacman"
    mkdir -p "${_CACHEDIR}"
    [[ -e "${1}/proc" ]] || mkdir -m 555 "${1}/proc"
    [[ -e "${1}/sys" ]] || mkdir -m 555 "${1}/sys"
    [[ -e "${1}/dev" ]] || mkdir -m 755 "${1}/dev"
    # mount special filesystems to ${1}
    echo "Mount special filesystems in ${1} ..."
    mount proc "${1}/proc" -t proc -o nosuid,noexec,nodev
    mount sys "${1}/sys" -t sysfs -o nosuid,noexec,nodev,ro
    mount udev "${1}/dev" -t devtmpfs -o mode=0755,nosuid
    mount devpts "${1}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm "${1}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
}

_create_pacman_conf() {
    if [[ -z "${_INSTALL_SOURCE}" ]]; then
        echo "Use default pacman.conf ..."
        _PACMAN_CONF="/etc/pacman.conf"
    else
        echo "Use custom pacman.conf ..."
        _PACMAN_CONF="$(mktemp "${1}"/pacman.conf.XXX)"
        #shellcheck disable=SC2129
        echo "[options]" >> "${_PACMAN_CONF}"
        echo "Architecture = auto" >> "${_PACMAN_CONF}"
        echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
        echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
        echo "ParallelDownloads = 5" >> "${_PACMAN_CONF}"
        echo "[archboot]" >> "${_PACMAN_CONF}"
        echo "Server = ${_INSTALL_SOURCE}" >> "${_PACMAN_CONF}"
    fi
}

_change_pacman_conf() {
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
    # disable checkspace option in pacman.conf, to allow to install packages in environment
    sed -i -e 's:^CheckSpace:#CheckSpace:g' "${1}"/etc/pacman.conf
}

# umount special filesystems
_umount_special() {
    echo "Umount special filesystems in ${1} ..."
    umount -R "${1}/proc"
    umount -R "${1}/sys"
    umount -R "${1}/dev"
}

_install_base_packages() {
    echo "Installing packages ${_PACKAGES} to ${1} ..."
    #shellcheck disable=SC2086
    pacman --root "${1}" -Sy ${_PACKAGES} --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --noconfirm --cachedir "${_CACHEDIR}" >/dev/null 2>&1
}

_install_archboot() {
    echo "Installing ${_ARCHBOOT} to ${1} ..."
    pacman --root "${1}" -Sy "${_ARCHBOOT}" --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --noconfirm --cachedir "${_CACHEDIR}" >/dev/null 2>&1
}

_aarch64_install_base_packages() {
    echo "Installing packages ${_PACKAGES} to ${1} ..."
    if [[ -e "$(basename "${_PACMAN_CONF}")" ]]; then 
        _PACMAN_CONF=$(basename "${_PACMAN_CONF}")
    fi
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Sy ${_PACKAGES} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
}

_aarch64_install_archboot() {
    if [[ -e "$(basename "${_PACMAN_CONF}")" ]]; then 
        _PACMAN_CONF=$(basename "${_PACMAN_CONF}")
    fi
    echo "Installing ${_ARCHBOOT} to ${1} ..."
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Sy ${_ARCHBOOT} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
}

_copy_mirrorlist_and_pacman_conf() {
    # copy local mirrorlist to container
    echo "Create pacman config and mirrorlist in container..."
    cp "/etc/pacman.d/mirrorlist" "${1}/etc/pacman.d/mirrorlist"
    # only copy from archboot pacman.conf, else use default file
    grep -qw 'archboot' /etc/hostname && cp /etc/pacman.conf "${1}"/etc/pacman.conf
}

_copy_archboot_defaults() {
    echo "Copy archboot defaults to container ..."
    cp /etc/archboot/defaults "${1}"/etc/archboot/defaults
}

_reproducibility() {
    echo "Reproducibility changes ..."
    sed -i -e '/INSTALLDATE/{n;s/.*/0/}' "${1}"/var/lib/pacman/local/*/desc
    rm "${1}"/var/cache/ldconfig/aux-cache
    rm "${1}"/etc/ssl/certs/java/cacerts
}

_set_hostname() {
    echo "Setting hostname to archboot ..."
    echo 'archboot' > "${1}/etc/hostname"
}
