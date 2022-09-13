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

_riscv64_pacman_chroot() {
    if ! [[ -f ${_PACMAN_RISCV64_CHROOT} && -f ${_PACMAN_RISCV64_CHROOT}.sig ]]; then
        echo "Downloading ${_PACMAN_RISCV64_CHROOT} ..."
        wget ${_ARCHBOOT_RISCV64_CHROOT_PUBLIC}/${_PACMAN_RISCV64_CHROOT}{,.sig} >/dev/null 2>&1
    else
        echo "Using local ${_PACMAN_RISCV64_CHROOT} ..."
    fi
    echo "Verifying ${_PACMAN_RISCV64_CHROOT} ..."
    gpg --verify "${_PACMAN_RISCV64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${1}" -xf "${_PACMAN_RISCV64_CHROOT}"
    if [[ -f ${_PACMAN_RISCV64_CHROOT} && -f ${_PACMAN_RISCV64_CHROOT}.sig ]]; then
        echo "Removing installation tarball ${_PACMAN_RISCV64_CHROOT} ..."
        rm ${_PACMAN_RISCV64_CHROOT}{,.sig}
    fi
    echo "Update container to latest packages..."
    systemd-nspawn -D "${1}" pacman -Syu --noconfirm >/dev/null 2>&1
}

# clean container from not needed files
_clean_container() {
    if [[ "${_CLEANUP_CONTAINER}" ==  "1" ]]; then
        echo "Clean container, delete not needed files from ${1} ..."
        rm -r "${1}"/usr/include
        rm -r "${1}"/usr/share/{aclocal,applications,audit,avahi,awk,bash-completion,common-lisp,dhclient,dhcpcd,dnsmasq,emacs,et,fish,gdb,gettext,gettext-[0-9]*,glib-[0-9]*,gnupg,gtk-doc,iana-etc,icons,icu,iptables,keyutils,libalpm,libgpg-error,makepkg-template,misc,mkinitcpio,ncat,ntp,p11-kit,pixmaps,pkgconfig,readline,screen,smartmontools,ss,tabset,vala,xml,xtables,zoneinfo-leaps,man,doc,info,perl[0-9]*,i18n,locale}
        rm -r "${1}"/usr/lib/{audit,avahi,awk,bash,binfmt.d,cifs-utils,cmake,coreutils,cryptsetup,cups,dracut,e2fsprogs,engines-[0-9]*,environment.d,gawk,getconf,gettext,girepository-[0-9]*,glib-[0-9]*,gnupg,gssproxy,guile,icu,itcl[0-9]*,iwd,krb5,ldb,ldscripts,libnl,ntfs-3g,p11-kit,pkgconfig,python[0-9]*,rsync,samba,sasl2,siconv,tar,tcl[0-9]*,tdbc[0-9]*,tdbcmysql[0-9]*,tdbcodbc[0-9]*,tdbcpostgres[0-9]*,terminfo,thread[0-9]*,xfsprogs,xtables}
        # until vim is fixed, clean all files and leave libperl.so
        find "${1}"/usr/lib/perl[0-9]* -type f ! -name 'libperl.so' -exec rm -rf {} \;
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
    grep -qw 'archboot' /etc/hostname && (echo "Cleaning archboot /var/cache/pacman/pkg ..."; rm -f /var/cache/pacman/pkg/*)
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
    echo "Update Arch Linux keyring ..."
    KEYRING="archlinux-keyring"
    [[ "$(uname -m)" == "aarch64" ]] && KEYRING="archlinux-keyring archlinuxarm-keyring"
    pacman -Sy --config "${_PACMAN_CONF}" --noconfirm --noprogressbar ${KEYRING}
}

#shellcheck disable=SC2120
_create_pacman_conf() {
    if [[ -z "${_INSTALL_SOURCE}" ]]; then
        echo "Use default pacman.conf ..."
        [[ "${2}" == "use_container_config" ]] && _PACMAN_CONF="${1}${_PACMAN_CONF}"
        if ! grep -qw "\[archboot\]" "${_PACMAN_CONF}"; then
            echo "Adding archboot repository to ${_PACMAN_CONF} ..."
            echo "[archboot]" >> "${_PACMAN_CONF}"
            echo "Server = https://pkgbuild.com/~tpowa/archboot/pkg" >> "${_PACMAN_CONF}"
        fi
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
    [[ "${_CLEANUP_CACHE}" == "1" ]] && _GRAPHICAL_PACKAGES=""
    [[ -d "${1}"/blankdb ]] || mkdir "${1}"/blankdb
    echo "Adding ${_GPG_KEY_ID} to trusted keys"
    pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
    pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    #shellcheck disable=SC2086
    if grep -qw archboot /etc/hostname; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3860000 ]]; then
            echo "Downloading ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
            pacman --root "${1}" -Syw --dbpath "${1}"/blankdb ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --cachedir "${_CACHEDIR}" --noconfirm >/dev/null 2>&1 || exit 1
        else
            echo "Downloading ${_ARCHBOOT} to ${1} ..."
             pacman --root "${1}" -Syw --dbpath "${1}"/blankdb ${_ARCHBOOT} --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --cachedir "${_CACHEDIR}" --noconfirm >/dev/null 2>&1 || exit 1
        fi
    else
        echo "Downloading ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
        pacman --root "${1}" -Syw --dbpath "${1}"/blankdb ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --cachedir "${_CACHEDIR}" --noconfirm >/dev/null 2>&1 || exit 1
    fi
    echo "Installing ${_ARCHBOOT} to ${1} ..."
    #shellcheck disable=SC2086
    pacman --root "${1}" -Sy ${_ARCHBOOT} --config "${_PACMAN_CONF}" --ignore systemd-resolvconf --noconfirm --cachedir "${_CACHEDIR}" >/dev/null 2>&1
    rm -r "${1}"/blankdb
}

_other_install_base_packages() {
    echo "Installing packages ${_PACKAGES} to ${1} ..."
    if [[ -e "${1}/$(basename "${_PACMAN_CONF}")" ]]; then
        _PACMAN_CONF=$(basename "${_PACMAN_CONF}")
    fi
    [[ -d "${1}"/blankdb ]] || mkdir "${1}"/blankdb
    echo "Downloading ${_PACKAGES} to ${1} ..."
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw --dbpath /blankdb ${_PACKAGES} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
    echo "Installing ${_PACKAGES} to ${1} ..."
    systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Sy ${_PACKAGES} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
}

_other_install_archboot() {
    # riscv64 need other packages
    [[ "$(echo $(systemd-nspawn -q -D "${1}" uname -m) | sed -e 's#\r##g')" == "riscv64" ]] && _GRAPHICAL_PACKAGES="${_XORG_PACKAGE} ${_WAYLAND_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_XFCE_PACKAGES} ${_PLASMA_PACKAGES}"
    [[ "${_CLEANUP_CACHE}" == "1" ]] && _GRAPHICAL_PACKAGES=""
    [[ -d "${1}"/blankdb ]] || mkdir "${1}"/blankdb
    if [[ -e "${1}/$(basename "${_PACMAN_CONF}")"  ]]; then
        _PACMAN_CONF=$(basename "${_PACMAN_CONF}")
    fi
    echo "Adding ${_GPG_KEY_ID} to trusted keys"
    [[ -d "${1}"/usr/share/archboot/gpg ]] || mkdir -p "${1}"/usr/share/archboot/gpg
    cp "${_GPG_KEY}" "${1}"/"${_GPG_KEY}"
    systemd-nspawn -q -D "${1}" pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    rm "${1}"/"${_GPG_KEY}"
    if grep -qw archboot /etc/hostname; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3860000 ]]; then
            echo "Downloading ${_ARCHBOOT} to ${1} ..."
            systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw --dbpath /blankdb ${_ARCHBOOT} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
        else
            echo "Downloading ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
            systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw --dbpath /blankdb ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
        fi
    else
        echo "Downloading ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} to ${1} ..."
        systemd-nspawn -q -D "${1}" /bin/bash -c "pacman -Syw --dbpath /blankdb ${_ARCHBOOT} ${_GRAPHICAL_PACKAGES} --config ${_PACMAN_CONF} --ignore systemd-resolvconf --noconfirm" >/dev/null 2>&1
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

_fix_groups() {
    echo "Recreate system groups ..."
    rm "${1}"/etc/{group,gshadow}
    systemd-nspawn -q -D "${1}" systemd-sysusers >/dev/null 2>&1
    # fix missing group in iwd FS#74646
    systemd-nspawn -q -D "${1}" groupadd netdev >/dev/null 2>&1
    # add missing groups
    systemd-nspawn -q -D "${1}" useradd -r -s /usr/bin/nologin -M -c 'PolicyKit daemon' -u 102 polkitd >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" groupadd -r -g 26 proc >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" groupmems -g proc -a polkitd >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" groupadd -r colord >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" groupadd -r -g 140 usbmux >/dev/null 2>&1
    # add missing groups on aarch64
    systemd-nspawn -q -D "${1}" groupadd -r -g 90 network >/dev/null 2>&1
    systemd-nspawn -q -D "${1}" groupadd -r tss >/dev/null 2>&1
}
