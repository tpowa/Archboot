#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_D_SCRIPTS=""
_L_COMPLETE=""
_L_INSTALL_COMPLETE=""
_G_RELEASE=""
_CONFIG="/etc/archboot/${_RUNNING_ARCH}-update_installer.conf"
_W_DIR="/archboot"
_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master"
_BIN="/usr/bin"
_ETC="/etc/archboot"
_LIB="/usr/lib/archboot"
_INST="/${_LIB}/installer"
_ZRAM_SIZE=${_ZRAM_SIZE:-"3G"}
[[ "${_RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-linux"
[[ "${_RUNNING_ARCH}" == "aarch64" ]] && VMLINUZ="Image"

usage () {
    echo -e "\033[1mUpdate installer, launch environments or create latest image files:\033[0m"
    echo -e "\033[1m-------------------------------------------------------------------\033[0m"
    echo -e "\033[1mPARAMETERS:\033[0m"
    echo -e " \033[1m-u\033[0m               Update scripts: setup, quickinst, tz, km and helpers."
    echo -e ""
    echo -e " \033[1m-latest\033[0m          Launch latest archboot environment (using kexec)."
    echo -e "                  This operation needs at least \033[1m2.3 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-latest-install\033[0m  Launch latest archboot environment with downloaded"
    echo -e "                  package cache (using kexec)."
    echo -e "                  This operation needs at least \033[1m3.2 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-latest-image\033[0m    Generate latest image files in /archboot directory"
    echo -e "                  This operation needs at least \033[1m5.0 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-launch-xfce\033[0m     Launch XFCE desktop with VNC sharing enabled."
    echo -e "                  This operation needs at least \033[1m3.5 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-h\033[0m               This message."
    exit 0
}

_archboot_check() {
    if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
        echo "This script should only be run in booted archboot environment. Aborting..."
        exit 1
    fi
}

_download_latest() {
    # Download latest setup and quickinst script from git repository
    if [[ "${_D_SCRIPTS}" == "1" ]]; then
        echo -e "\033[1mStart:\033[0m Downloading latest km, tz, quickinst, setup and helpers..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        BINS="copy-mountpoint.sh rsync-backup.sh restore-usbstick.sh \
        ${_RUNNING_ARCH}-create-container.sh ${_RUNNING_ARCH}-release.sh \
        binary-check.sh update-installer.sh secureboot-keys.sh mkkeys.sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        BINS="quickinst setup km tz"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        LIBS="common.sh container.sh release.sh iso.sh update-installer.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_LIB}/${i}?inline=false" -O "${_LIB}/${i}"
        done
        SETUPS="autoconfiguration.sh autoprepare.sh base.sh blockdevices.sh bootloader.sh btrfs.sh common.sh \
                configuration.sh mountpoints.sh network.sh pacman.sh partition.sh storage.sh"
        for i in ${SETUPS}; do
            wget -q "${_SOURCE}${_INST}/${i}?inline=false" -O "${_INST}/${i}"
        done
        echo -e "\033[1mFinished:\033[0m Downloading scripts done."
        exit 0
    fi
}

_update_installer_check() {
    if [[ -f /.update-installer ]]; then
        echo -e "\033[91mAborting:\033[0m"
        echo "update-installer.sh is already running on other tty ..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
}

_umount_w_dir() {
    if mountpoint -q "${_W_DIR}"; then
        echo "Unmounting ${_W_DIR} ..." > /dev/tty7
        # umount all possible mountpoints
        umount -R "${_W_DIR}"
        echo 1 > /sys/block/zram0/reset
        # wait 5 seconds to get RAM cleared and set free
        sleep 5
    fi
}

_zram_mount() {
    # add defaults
    _ZRAM_ALGORITHM=${_ZRAM_ALGORITHM:-"zstd"}
    modprobe zram > /dev/tty7 2>&1
    echo "${_ZRAM_ALGORITHM}" >/sys/block/zram0/comp_algorithm
    echo "${1}" >/sys/block/zram0/disksize
    echo "Creating btrfs filesystem with ${_DISKSIZE} on /dev/zram0 ..." > /dev/tty7
    mkfs.btrfs -q --mixed /dev/zram0 > /dev/tty7 2>&1
    [[ -d "${_W_DIR}" ]] || mkdir "${_W_DIR}"
    # use -o discard for RAM cleaning on delete
    # (online fstrimming the block device!)
    # fstrim <mountpoint> for manual action
    # it needs some seconds to get RAM free on delete!
    mount -o discard /dev/zram0 "${_W_DIR}" > /dev/tty7 2>&1
}

_clean_archboot() {
    # remove everything not necessary
    rm -rf "/usr/lib/firmware"
    rm -rf "/usr/lib/modules"
    rm -rf /usr/lib/{libicu*,libstdc++*}
    _SHARE_DIRS="archboot efitools file grub hwdata kbd licenses lshw nmap nano openvpn pacman refind systemd tc usb_modeswitch vim zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    systemctl stop pacman-init.service
}

_create_container() {
    # create container without package cache
    if [[ "${_L_COMPLETE}" == "1" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for local image
        # add the db too on reboot
        install -D -m644 /var/cache/pacman/pkg/archboot.db "${_W_DIR}"/var/cache/pacman/pkg/archboot.db
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            mv /var/cache/pacman/pkg/* ${_W_DIR}/var/cache/pacman/pkg/
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///${_W_DIR}/var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
        fi
    else
        #online mode
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
            mv "${_W_DIR}"/var/cache/pacman/pkg /var/cache/pacman/
        fi
    fi
}

_kver_x86() {
    # get kernel version from installed kernel
    if [[ -f "/${VMLINUZ}" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/${VMLINUZ}")
        read -r _HWKVER _ < <(dd if="/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
    fi
    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_kver_generic() {
    # get kernel version from installed kernel
    read -r _ _ _HWKVER _ < <(grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+' "/${VMLINUZ}")

    # try if the image is gzip compressed
    if [[ -z "${_HWKVER}" ]]; then
        read -r _ _ _HWKVER _ < <(gzip -c -d "/${VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi

    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_create_initramfs() {
    # move cache back to initramfs directory in online mode
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            if [[ -d /var/cache/pacman/pkg ]]; then
                mv /var/cache/pacman/pkg ${_W_DIR}/tmp/var/cache/pacman/
            fi
        fi
    fi
    #from /usr/bin/mkinitcpio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    bsdtar --null -cf - --format=newc @- | zstd -T0 -10> /initrd.img &
    sleep 2
    for i in $(find . -mindepth 1 -type f | sort); do
        rm "${i}" >/dev/null 2>&1
        sleep 0.002
    done
    while pgrep -x bsdtar >/dev/null 2>&1; do
        sleep 1
    done
}

_kexec() {
    # load kernel and initrds into running kernel in background mode!
    kexec -l /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline&
    # wait 2 seconds for getting a complete initramfs
    # remove kernel and initrd to save RAM for kexec in background
    sleep 2
    rm /{initrd.img,${VMLINUZ}}
    while pgrep -x kexec >/dev/null 2>&1; do
        sleep 1
    done
    echo -e "\033[1mFinished:\033[0m Rebooting in a few seconds ..."
    # don't show active prompt wait for kexec to be launched
    while true; do
        if [[ -e "/sys/firmware/efi" ]]; then
            # UEFI kexec call
            systemctl kexec 2>/dev/null
        else
            # BIOS kexec call
            kexec -e 2>/dev/null
        fi
        sleep 1
    done
}
_cleanup_xfce() {
    echo "Cleanup archboot environment ..."
    rm -rf /usr/share/{man,info,doc,gtk-doc,ibus,perl5}
    rm -rf /usr/include
    rm -rf /usr/lib/libgo.*
}

_launch_xfce() {
    X_PACKAGES="llvm-libs gcc-libs perl glibc xorg libtiff glib2 chromium libcups harfbuzz \
    avahi nss breeze-icons tigervnc p11-kit libp11-kit gvfs fuse tpm2-tss \
    libsecret gparted gvfs-smb smbclient libcap tevent libbsd libldap tdb ldb \
    libmd jansson libsasl xfce4 thunar-archive-plugin thunar-volman file-roller \
    nss-mdns gnome-keyring"
    # try to save RAM by calling the cleanup hook and installing each package alone
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo "Install packages ..."
        _INSTALL_SOURCE="file:///var/cache/pacman/pkg"
        _create_pacman_conf
        pacman -Sy --config ${_PACMAN_CONF}
        for i in ${X_PACKAGES}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --config ${_PACMAN_CONF} --noconfirm || exit 1
            _cleanup_xfce
        done
    else
        echo "Updating environment ..."
        pacman -Syu --ignore linux --ignore linux-firmware --ignore linux-firmware-marvell --noconfirm || exit 1
        _clean_xfce
        echo "Install packages ..."
        for i in ${X_PACKAGES}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --noconfirm || exit 1
            _clean_xfce
        done
    fi
    # fix locale
    echo "Fix locale ..."
    sed -i -e 's:#C.UTF-8 UTF-8:C.UTF-8 UTF-8:g' "${1}/etc/locale.gen"
    locale-gen
    rm -rf /usr/share/{locale,i18n}
    # replace appfinder with archboot setup
    sed -i -e 's#xfce4-appfinder#archboot#g' /etc/xdg/xfce4/panel/default.xml
    echo "Fix chromium startup ..."
    # fix chromium startup
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
wiki.archlinux.org/title/Archboot
EOF
    echo "Fix xfce4 defaults ..."
    # fix xfce4 defaults
    # breeze icons
    sed -i -e 's#<property name="IconThemeName" type="string" value="Adwaita"/>#<property name="IconThemeName" type="string" value="breeze"/>#g' \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
    sed -i -e 's#firefox#chromium#g' /etc/xdg/xfce4/helpers.rc
    # fix gparted.desktop
    sed -i -e 's#Categories=.*#Categories=X-Xfce-Toplevel;#g' /usr/share/applications/gparted.desktop
    # xfce menu
    cat << EOF >/etc/xdg/menus/xfce-applications.menu
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
    <Name>Xfce</Name>

    <DefaultAppDirs/>
    <DefaultDirectoryDirs/>

    <Include>
        <Category>X-Xfce-Toplevel</Category>
    </Include>

    <Layout>
	<Filename>archboot.desktop</Filename>
        <Filename>gparted.desktop</Filename>
        <Filename>xfce4-run.desktop</Filename>
        <Separator/>
        <Filename>xfce4-terminal-emulator.desktop</Filename>
        <Filename>xfce4-file-manager.desktop</Filename>
	<Filename>xfce4-web-browser.desktop</Filename>
        <Separator/>
        <Menuname>Settings</Menuname>
        <Separator/>
        <Merge type="all"/>
        <Separator/>
        <Filename>xfce4-session-logout.desktop</Filename>
    </Layout>

    <Menu>
        <Name>Settings</Name>
        <Directory>xfce-settings.directory</Directory>
        <Include>
            <Category>Settings</Category>
        </Include>

        <Layout>
            <Filename>xfce-settings-manager.desktop</Filename>
            <Separator/>
            <Merge type="all"/>
        </Layout>

        <Menu>
            <Name>Screensavers</Name>
            <Directory>xfce-screensavers.directory</Directory>
            <Include>
                <Category>Screensaver</Category>
            </Include>
        </Menu>
    </Menu>

    <DefaultMergeDirs/>

</Menu>
EOF
    # background image
    cat << EOF >/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="last-single-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="image-show" type="bool" value="true"/>
        <property name="image-style" type="int" value="0"/>
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
      <property name="monitorHDMI1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
    # hide menu entries
    for i in xfce4-mail-reader xfce4-about; do
        echo 'NoDisplay=true' >> /usr/share/applications/$i.desktop
    done
    echo "Autostart setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
Exec=xfce4-terminal -x /usr/bin/setup
Icon=system-software-install
Categories=X-Xfce-Toplevel;
EOF
echo "Set VNC password ..."
echo 'archboot' | vncpasswd -f > /etc/tigervnc/passwd
    echo "Autostart tigervnc ..."
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Starting avahi-daemon ..."
    systemctl start avahi-daemon.service
    echo "Launching XFCE ..."
    startxfce4
}
