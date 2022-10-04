#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
LANG="C"
_BASENAME="$(basename "${0}")"
_RUNNING_ARCH="$(uname -m)"
_PACMAN_MIRROR="/etc/pacman.d/mirrorlist"
_PACMAN_CONF="/etc/pacman.conf"
_FIX_PACKAGES="libunwind libelf libevent python talloc gdbm fuse3 gcc-libs perl glibc libtiff glib2 libcups harfbuzz avahi nss p11-kit libp11-kit fuse tpm2-tss libsecret smbclient libcap tevent libbsd libldap tdb ldb libmd jansson libsasl pcre2"
_XORG_PACKAGE="xorg"
_VNC_PACKAGE="tigervnc"
_WAYLAND_PACKAGE="egl-wayland"
_STANDARD_PACKAGES="gparted nss-mdns"
# chromium is now working on riscv64
[[ "${_RUNNING_ARCH}" == "riscv64" ]] && _STANDARD_BROWSER="firefox"
_GRAPHICAL_PACKAGES="${_XORG_PACKAGE} ${_WAYLAND_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_XFCE_PACKAGES} ${_GNOME_PACKAGES} ${_PLASMA_PACKAGES}"
_NSPAWN="systemd-nspawn -q -D"

### check for root
_root_check() {
    if ! [[ ${UID} -eq 0 ]]; then
        echo "ERROR: Please run as root user!"
        exit 1
    fi
}

### check for x86_64
_x86_64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        echo "ERROR: Pleae run on x86_64 hardware."
        exit 1
    fi
}

### check for aarch64
_aarch64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        echo "ERROR: Please run on aarch64 hardware."
        exit 1
    fi
}

### check for aarch64
_riscv64_check() {
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo "ERROR: Please run on riscv64 hardware."
        exit 1
    fi
}

### check if running in container
_container_check() {
    if grep -q bash /proc/1/sched ; then
        echo "ERROR: Running inside container. Aborting..."
        exit 1
    fi
}

### check for tpowa's build server
_buildserver_check() {
    if [[ ! "$(cat /etc/hostname)" == "T-POWA-LX" ]]; then
        echo "This script should only be run on tpowa's build server. Aborting..."
        exit 1
    fi
}

_generate_keyring() {
    # use fresh one on normal systems
    # copy existing gpg cache on archboot usage
    if ! grep -qw archboot /etc/hostname; then
        # generate pacman keyring
        echo "Generate pacman keyring in container ..."
        ${_NSPAWN} "${1}" pacman-key --init >/dev/null 2>&1
        ${_NSPAWN} "${1}" pacman-key --populate >/dev/null 2>&1
    else
        cp -ar /etc/pacman.d/gnupg "${1}"/etc/pacman.d >/dev/null 2>&1
    fi
}

_x86_64_pacman_use_default() {
    # use pacman.conf with disabled [testing] repository
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "Use system's ${_PACMAN_CONF} ..."
    else
        echo "Copy ${_CUSTOM_PACMAN_CONF} to ${_PACMAN_CONF} ..."
        cp "${_PACMAN_CONF}" "${_PACMAN_CONF}".old
        cp "${_CUSTOM_PACMAN_CONF}" "${_PACMAN_CONF}"
    fi
    # use mirrorlist with enabled rackspace mirror
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "Use system's ${_PACMAN_MIRROR} ..."    
    else
        echo "Copy ${_CUSTOM_MIRRORLIST} to ${_PACMAN_MIRROR} ..."
        cp "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}".old
        cp "${_CUSTOM_MIRRORLIST}" "${_PACMAN_MIRROR}"
    fi
}

_x86_64_pacman_restore() {
    # restore pacman.conf and mirrorlist
    if [[ -z "${_CUSTOM_PACMAN_CONF}" ]]; then
        echo "System's ${_PACMAN_CONF} used ..."
    else
        echo "Restore system's ${_PACMAN_CONF} ..."
         cp "${_PACMAN_CONF}".old "${_PACMAN_CONF}"
    fi
    if [[ -z "${_CUSTOM_MIRRORLIST}" ]]; then
        echo "System's ${_PACMAN_MIRROR} used ..."
    else
        echo "Restore system's ${_PACMAN_MIRROR} ..."
        cp "${_PACMAN_MIRROR}".old "${_PACMAN_MIRROR}"
    fi    
}

_fix_network() {
    echo "Fix network settings in ${1} ..."
    # enable parallel downloads
    sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${1}"/etc/pacman.conf
    # fix network in container
    rm "${1}"/etc/resolv.conf
    echo "nameserver 8.8.8.8" > "${1}"/etc/resolv.conf
}

_create_archboot_db() {
    echo "Creating archboot repository db ..."
    #shellcheck disable=SC2046
    LANG=C repo-add -q "${1}"/archboot.db.tar.gz $(find "${1}"/ -type f ! -name '*.sig')
}

_pacman_parameters() {
    # building for different architecture using binfmt
    if [[ "${2}" == "use_binfmt" ]]; then
        _PACMAN="${_NSPAWN} ${1} pacman"
        _PACMAN_CACHEDIR=""
        _PACMAN_DB="--dbpath /blankdb"
    # building for running architecture
    else
        _PACMAN="pacman --root ${1}"
        _PACMAN_CACHEDIR="--cachedir ${_CACHEDIR}"
        _PACMAN_DB="--dbpath ${1}/blankdb"
    fi
    [[ -d "${1}"/blankdb ]] || mkdir "${1}"/blankdb
    # defaults used on every pacman call
    _PACMAN_DEFAULTS="--config ${_PACMAN_CONF} ${_PACMAN_CACHEDIR} --ignore systemd-resolvconf --noconfirm"
}

_pacman_key() {
    echo "Adding ${_GPG_KEY} to container ..."
    [[ -d "${1}"/usr/share/archboot/gpg ]] || mkdir -p "${1}"/usr/share/archboot/gpg
    cp "${_GPG_KEY}" "${1}"/"${_GPG_KEY}"
    echo "Adding ${_GPG_KEY_ID} to container trusted keys"
    ${_NSPAWN} ${1} pacman-key --add "${_GPG_KEY}" >/dev/null 2>&1
    ${_NSPAWN} ${1} pacman-key --lsign-key "${_GPG_KEY_ID}" >/dev/null 2>&1
    echo "Removing "${_GPG_KEY}" from container ..."
    rm "${1}/${_GPG_KEY}"
}

_riscv64_disable_graphics() {
    # riscv64 need does not support local image at the moment
    _CONTAINER_ARCH="$(${_NSPAWN} ${1} uname -m)"
    #shellcheck disable=SC2001
    [[ "$(echo "${_CONTAINER_ARCH}" | sed -e 's#\r##g')" == "riscv64" ]] && _GRAPHICAL_PACKAGES=""
}

_cachedir_check() {
    if grep -q ^CacheDir /etc/pacman.conf; then
        echo "Error: CacheDir is set in /etc/pacman.conf. Aborting ..."
        exit 1
    fi
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop ..."
        _configure_plasma >/dev/tty7 2>&1
    else
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop already done ..."
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop already done ..."
    fi
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop ..."
        _configure_gnome >/dev/tty7 2>&1
        systemd-sysusers >/dev/tty7 2>&1
        systemd-tmpfiles --create >/dev/tty7 2>&1
    else
        echo -e "\033[1mStep 3/5:\033[0m Installing GNOME desktop already done ..."
        echo -e "\033[1mStep 4/5:\033[0m Configuring GNOME desktop already done ..."
    fi
}

_configure_gnome() {
    echo "Configuring Gnome ..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper ..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal -- /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries ..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_configure_plasma() {
    echo "Configuring KDE ..."
    sed -i -e 's#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,preferred://browser,applications:gparted.desktop,applications:archboot.desktop</default>#g' /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper ..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure ..."
    cat << EOF >/etc/xdg/menus/applications.menu
 <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<!-- Search the default locations -->
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Separator/>
		<Menuname>More</Menuname>
	</DefaultLayout>
	<Layout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Menuname>Applications</Menuname>
	</Layout>
	<Menu>
		<Name>Settingsmenu</Name>
		<Directory>kf5-settingsmenu.directory</Directory>
		<Include>
			<Category>Settings</Category>
		</Include>
	</Menu>
	<DefaultMergeDirs/>
	<Include>
	<Filename>archboot.desktop</Filename>
	<Filename>${_STANDARD_BROWSER}.desktop</Filename>
	<Filename>org.kde.dolphin.desktop</Filename>
	<Filename>gparted.desktop</Filename>
	<Filename>org.kde.konsole.desktop</Filename>
	</Include>
</Menu>
EOF
    echo "Autostarting setup ..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=konsole -p colors=Linux -e /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}
