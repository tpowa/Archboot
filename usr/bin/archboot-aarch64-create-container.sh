#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR="$1/var/cache/pacman/pkg"
_CLEANUP_CACHE=""
_SAVE_RAM=""
_LINUX_FIRMWARE="linux-firmware"
_DIR=""
_PACMAN_AARCH64_CHROOT_SERVER="https://pkgbuild.com/~tpowa/archboot-helper/pacman-chroot-aarch64"
_PACMAN_AARCH64_CHROOT="pacman-aarch64-chroot-latest.tar.zst"

usage () {
    echo "CREATE ARCHBOOT CONTAINER"
    echo "-----------------------------"
    echo "This will create an archboot container for an archboot image."
    echo "Usage: ${_BASENAME} <directory> <options>"
    echo " Options:"
    echo "  -cc    Cleanup container eg. remove manpages, includes ..."
    echo "  -cp    Cleanup container package cache"
    exit 0
}

cleancache() {
    if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
        # clean cache
        echo "Clean pacman cache from ${_DIR} ..."
        rm -r "${_DIR}"/var/cache/pacman
    fi
}

saveram() {
    if [[ "${_SAVE_RAM}" ==  "1" ]]; then
        # clean container from not needed files
        echo "Clean container, delete not needed files from ${_DIR} ..."
        rm -r "${_DIR}"/usr/include
        rm -r "${_DIR}"/usr/share/{aclocal,applications,audit,avahi,awk,bash-completion,cmake,common-lisp,cracklib,dhclient,dhcpcd,dict,dnsmasq,emacs,et,fish,gdb,gettext,gettext-0.21,glib-2.0,gnupg,graphite2,gtk-doc,iana-etc,icons,icu,iptables,keyutils,libalpm,libgpg-error,makepkg-template,misc,mkinitcpio,ncat,ntp,p11-kit,pixmaps,pkgconfig,readline,screen,smartmontools,ss,stoken,tabset,texinfo,vala,xml,xtables,zoneinfo-leaps,man,doc,info,perl5}
        rm -r "${_DIR}"/usr/lib/{audit,avahi,awk,bash,binfmt.d,cifs-utils,cmake,coreutils,cryptsetup,cups,dracut,e2fsprogs,engines-1.1,environment.d,gawk,getconf,gettext,girepository-1.0,glib-2.0,gnupg,gssproxy,guile,icu,itcl4.2.2,iwd,krb5,ldb,ldscripts,libnl,libproxy,named,ntfs-3g,openconnect,openssl-1.0,p11-kit,pcsc,perl5,pkcs11,pkgconfig,python3.10,rsync,samba,sasl2,siconv,sysctl.d,sysusers.d,tar,tcl8.6,tcl8,tdbc1.1.3,tdbcmysql1.1.3,tdbcodbc1.1.3,tdbcpostgres1.1.3,terminfo,texinfo,thread2.8.7,valgrind,xfsprogs,xplc-0.3.13,xtables}
    fi
}

[[ -z "${1}" ]] && usage

_DIR="$1"

while [ $# -gt 0 ]; do
    case ${1} in
        -cc|--cc) _SAVE_RAM="1" ;;
        -cp|--cp) _CLEANUP_CACHE="1" ;;
    esac
    shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then
    echo "ERROR: Please run as root user!"
    exit 1
fi

echo "Starting container creation ..."
echo "Create directory ${_DIR} ..."
mkdir "${_DIR}"
if [[ "$(uname -m)" == "aarch64" ]]; then
    # prepare pacman dirs
    echo "Create directories in ${_DIR} ..."
    mkdir -p "${_DIR}"/var/lib/pacman
    mkdir -p "${_CACHEDIR}"
    [[ -e "${_DIR}/proc" ]] || mkdir -m 555 "${_DIR}/proc"
    [[ -e "${_DIR}/sys" ]] || mkdir -m 555 "${_DIR}/sys"
    [[ -e "${_DIR}/dev" ]] || mkdir -m 755 "${_DIR}/dev"
    # mount special filesystems to ${_DIR}
    echo "Mount special filesystems in ${_DIR} ..."
    mount proc "${_DIR}/proc" -t proc -o nosuid,noexec,nodev
    mount sys "${_DIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
    mount udev "${_DIR}/dev" -t devtmpfs -o mode=0755,nosuid
    mount devpts "${_DIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm "${_DIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    # install archboot
    echo "Installing packages base linux and ${_LINUX_FIRMWARE} to ${_DIR} ..."
    pacman --root "${_DIR}" -Sy base linux "${_LINUX_FIRMWARE}" --ignore systemd-resolvconf --noconfirm --cachedir "${_PWD}"/"${_CACHEDIR}" >/dev/null 2>&1
    rm "${_DIR}"/boot/{initramfs-linux.img,initramfs-linux-fallback.img}
    saveram
    cleancache
    echo "Installing archboot to ${_DIR} ..."
    pacman --root "${_DIR}" -Sy archboot-arm --ignore systemd-resolvconf --noconfirm >/dev/null 2>&1
    cleancache
    # Clean cache on archboot environment
    if [[ "$(cat /etc/hostname)" == "archboot" ]]; then
        echo "Cleaning /var/cache/pacman/pkg ..."
        rm -r /var/cache/pacman/pkg
    fi
    # umount special filesystems
    echo "Umount special filesystems in to ${_DIR} ..."
    umount -R "${_DIR}/proc"
    umount -R "${_DIR}/sys"
    umount -R "${_DIR}/dev"
    # generate locales
    echo "Create locales in container ..."
    systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen" >/dev/null 2>&1
    systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen" >/dev/null 2>&1
    systemd-nspawn -D "${_DIR}" locale-gen >/dev/null 2>&1
    [[ "${_SAVE_RAM}" ==  "1" ]] && rm -r "${_DIR}"/usr/share/{i18n,locale}
    # generate pacman keyring
    echo "Generate pacman keyring in container ..."
    systemd-nspawn -D "${_DIR}" pacman-key --init >/dev/null 2>&1
    systemd-nspawn -D "${_DIR}" pacman-key --populate archlinuxarm >/dev/null 2>&1
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}"/etc/pacman.conf
fi
if [[ "$(uname -m)" == "x86_64" ]]; then
    echo "Downloading archlinuxarm pacman aarch64 chroot..."
    ! [[ -f pacman-aarch64-chroot-latest.tar.zst ]] && wget ${_PACMAN_AARCH64_CHROOT_SERVER}/${_PACMAN_AARCH64_CHROOT}{,.sig} >/dev/null 2>&1
    # verify dowload
    sleep 1
    gpg --verify "${_PACMAN_AARCH64_CHROOT}.sig" >/dev/null 2>&1 || exit 1
    bsdtar -C "${_DIR}" -xf "${_PACMAN_AARCH64_CHROOT}"
    echo "Removing installation tarball ..."
    rm ${_PACMAN_AARCH64_CHROOT}{,.sig}
fi
    # disable checkspace option in pacman.conf, to allow to install packages in environment
    sed -i -e 's:^CheckSpace:#CheckSpace:g' "${_DIR}"/etc/pacman.conf
if [[ "$(uname -m)" == "x86_64" ]]; then
    # update container to latest packages
    echo "Update container to latest packages..."
    systemd-nspawn -D "${_DIR}" pacman -Syu --noconfirm >/dev/null 2>&1
    echo "Installing archboot-arm and ${_LINUX_FIRMWARE} to container..."
    systemd-nspawn -D "${_DIR}" /bin/bash -c "pacman -S archboot-arm ${_LINUX_FIRMWARE} --noconfirm" >/dev/null 2>&1
    rm "${_DIR}"/boot/{initramfs-linux.img,initramfs-linux-fallback.img}
    cleancache
    saveram
    [[ "${_SAVE_RAM}" ==  "1" ]] && rm -r "${_DIR}"/usr/share/{i18n,locale}
fi
echo "Setting hostname to archboot ..."
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo archboot > /etc/hostname" >/dev/null 2>&1
echo "Finished container setup in ${_DIR} ."
