#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>

_cleanup_install() {
    rm -rf /usr/share/{man,help,gir-[0-9]*,info,doc,gtk-doc,ibus,perl[0-9]*}
    rm -rf /usr/include
    rm -rf /usr/lib/libgo.*
}

_cleanup_cache() {
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(grep 'installed' /var/log/pacman.log | cut -d ' ' -f 4); do
        rm -rf /var/cache/pacman/pkg/"${i}"-[0-9]*
    done
}

_prepare_graphic() {
    _GRAPHIC="${1}"
    if [[ ! -e "/.full_system" ]]; then
        _progress "2" "Removing firmware files..."
        rm -rf /usr/lib/firmware
        # fix libs first, then install packages from defaults
        _GRAPHIC="${1}"
    fi
    touch /.archboot
    (_IGNORE=""
    if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
        for i in ${_GRAPHIC_IGNORE}; do
            _IGNORE="${_IGNORE} --ignore ${i}"
        done
    fi
    #shellcheck disable=SC2086
    pacman -Syu ${_IGNORE} --noconfirm &>"${_LOG}"
    [[ ! -e "/.full_system" ]] && _cleanup_install
    rm /.archboot) &
    _progress_wait "3" "10" "Updating environment to latest packages..." "5"
    # check for qxl module
    if grep -q qxl /proc/modules; then
        echo "${_GRAPHIC}" | grep -q xorg && _GRAPHIC="${_GRAPHIC} xf86-video-qxl"
    fi
    for i in ${_FIX_PACKAGES}; do
        #shellcheck disable=SC2086
        _progress "11" "Installing ${i} ..."
        pacman -S ${i} --noconfirm &>"${_LOG}"
        [[ ! -e "/.full_system" ]] && _cleanup_install
        [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
        rm -f /var/log/pacman.log
    done
    touch /.archboot
    (for i in ${_GRAPHIC}; do
        #shellcheck disable=SC2086
        pacman -S ${i} --noconfirm &>"${_LOG}"
        [[ ! -e "/.full_system" ]] && _cleanup_install
        [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
        rm -f /var/log/pacman.log
    done
    # install firefox langpacks
    if [[ "${_STANDARD_BROWSER}" == "firefox" ]]; then
        _LANG="be bg cs da de el fi fr hu it lt lv mk nl nn pl ro ru sk sr uk"
        for i in ${_LANG}; do
            if grep -q "${i}" /etc/locale.conf; then
                pacman -S firefox-i18n-"${i}" --noconfirm &>"${_LOG}"
            fi
        done
        if grep -q en_US /etc/locale.conf; then
            pacman -S firefox-i18n-en-us --noconfirm &>"${_LOG}"
        elif grep -q 'C.UTF-8' /etc/locale.conf; then
            pacman -S firefox-i18n-en-us --noconfirm &>"${_LOG}"
        elif grep -q es_ES /etc/locale.conf; then
            pacman -S firefox-i18n-es-es --noconfirm &>"${_LOG}"
        elif grep -q pt_PT /etc/locale.conf; then
            pacman -S firefox-i18n-pt-pt --noconfirm &>"${_LOG}"
        elif grep -q sv_SE /etc/locale.conf; then
            pacman -S firefox-i18n-sv-se --noconfirm &>"${_LOG}"
        fi
    fi
    rm /.archboot ) &
    _progress_wait "11" "59" "Running pacman..." "0.5"
    if [[ ! -e "/.full_system" ]]; then
        _progress "70" "Removing not used icons..."
        rm -rf /usr/share/icons/breeze-dark
        _progress "80" "Cleanup locale and i18n..."
        find /usr/share/locale/ -mindepth 2 ! -path '*/be/*' ! -path '*/bg/*' ! -path '*/cs/*' \
        ! -path '*/da/*' ! -path '*/de/*' ! -path '*/en/*' ! -path '*/el/*' ! -path '*/es/*' \
        ! -path '*/fi/*' ! -path '*/fr/*' ! -path '*/hu/*' ! -path '*/it/*' ! -path '*/lt/*' \
        ! -path '*/lv/*' ! -path '*/mk/*' ! -path '*/nl/*' ! -path '*/nn/*' ! -path '*/pl/*' \
        ! -path '*/pt/*' ! -path '*/ro/*' ! -path '*/ru/*' ! -path '*/sk/*' ! -path '*/sr/*' \
        ! -path '*/sv/*' ! -path '*/uk/*' -delete &>"${_NO_LOG}"
        find /usr/share/i18n/charmaps ! -name 'UTF-8.gz' -delete &>"${_NO_LOG}"
    fi
    _progress "90" "Restart dbus..."
    systemd-sysusers >"${_LOG}" 2>&1
    systemd-tmpfiles --create >"${_LOG}" 2>&1
    # fixing dbus requirements
    systemctl reload dbus
    systemctl reload dbus-org.freedesktop.login1.service
}

_hint_graphic_installed () {
    echo -e "\e[1;91mError: Graphical environment already installed...\e[m"
    echo -e "You are running in \e[1mOffline Mode\e[m with less than \e[1m4500 MB RAM\e[m, which only can launch \e[1mone\e[m environment."
    echo -e "Please relaunch your already used graphical environment from commandline."
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop..."
        _configure_gnome >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop already done..."
    fi
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop..."
        _configure_plasma >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop already done..."
    fi
}

_prepare_sway() {
    if ! [[ -e /usr/bin/sway ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing Sway desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >"${_LOG}" 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring Sway desktop..."
        _configure_sway >"${_LOG}" 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing Sway desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring Sway desktop already done..."
    fi
}

_configure_gnome() {
    echo "Configuring Gnome..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup..."
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
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_configure_plasma() {
    echo "Configuring KDE..."
    sed -i -e "s#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,applications:${_STANDARD_BROWSER}.desktop,applications:gparted.desktop,applications:archboot.desktop</default>#g" /usr/share/plasma/plasmoids/org.kde.plasma.tasvconsoleanager/contents/config/main.xml
    echo "Replacing wallpaper..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure..."
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
    echo "Autostarting setup..."
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

_configure_sway() {
    echo "Configuring Sway..."
    echo "Configuring bemenu..."
    sed -i -e 's|^set $menu.*|set $menu j4-dmenu-desktop --dmenu=\x27bemenu -i --tf "#00ff00" --hf "#00ff00" --nf "#dcdccc" --fn "pango:Terminus 12" -H 30\x27 --no-generic --term="foot"|g'  /etc/sway/config
    echo "Configuring wallpaper..."
    sed -i -e 's|^output .*|output * bg /usr/share/archboot/grub/archboot-background.png fill|g' /etc/sway/config
    echo "Configuring foot..."
    if ! grep -q 'archboot colors' /etc/xdg/foot/foot.ini; then
cat <<EOF >> /etc/xdg/foot/foot.ini
# archboot colors
[colors]
background=000000
foreground=ffffff

## Normal/regular colors (color palette 0-7)
regular0=000000   # bright black
regular1=ff0000   # bright red
regular2=00ff00   # bright green
regular3=ffff00   # bright yellow
regular4=005fff   # bright blue
regular5=ff00ff   # bright magenta
regular6=00ffff   # bright cyan
regular7=ffffff   # bright white

## Bright colors (color palette 8-15)
bright0=000000   # bright black
bright1=ff0000   # bright red
bright2=00ff00   # bright green
bright3=ffff00   # bright yellow
bright4=005fff   # bright blue
bright5=ff00ff   # bright magenta
bright6=00ffff   # bright cyan
bright7=ffffff   # bright white

[main]
font=monospace:size=12
EOF

    fi
    echo "Autostarting setup..."
    grep -q 'exec foot' /etc/sway/config ||\
        echo "exec foot -- /usr/bin/setup" >> /etc/sway/config
    if ! grep -q firefox /etc/sway/config; then
        cat <<EOF >> /etc/sway/config
# from https://wiki.gentoo.org/wiki/Sway
# automatic floating
for_window [window_role = "pop-up"] floating enable
for_window [window_role = "bubble"] floating enable
for_window [window_role = "dialog"] floating enable
for_window [window_type = "dialog"] floating enable
for_window [window_role = "task_dialog"] floating enable
for_window [window_type = "menu"] floating enable
for_window [app_id = "floating"] floating enable
for_window [app_id = "floating_update"] floating enable, resize set width 1000px height 600px
for_window [class = "(?i)pinentry"] floating enable
for_window [title = "Administrator privileges required"] floating enable
# firefox tweaks
for_window [title = "About Mozilla Firefox"] floating enable
for_window [window_role = "About"] floating enable
for_window [app_id="firefox" title="Library"] floating enable, border pixel 1, sticky enable
for_window [title = "Firefox - Sharing Indicator"] kill
for_window [title = "Firefox — Sharing Indicator"] kill
EOF
    fi
    echo "Configuring desktop files..."
    cat << EOF > /usr/share/applications/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=foot -- /usr/bin/setup
Icon=system-software-install
EOF
    _HIDE_MENU="avahi-discover bssh bvnc org.codeberg.dnkl.foot-server org.codeberg.dnkl.footclient qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
    echo "Configuring waybar..."
    if ! grep -q 'exec waybar' /etc/sway/config; then
        # hide sway-bar
        sed -i '/position top/a mode invisible' /etc/sway/config
        # diable not usable plugins
        echo "exec waybar" >> /etc/sway/config
        sed -i -e 's#, "custom/media"##g' /etc/xdg/waybar/config
        sed -i -e 's#"mpd", "idle_inhibitor", "pulseaudio",##g' /etc/xdg/waybar/config
    fi
    echo "Configuring wayvnc..."
     if ! grep -q wayvnc /etc/sway/config; then
        echo "address=0.0.0.0" > /etc/wayvnc
        echo "exec wayvnc -C /etc/wayvnc &" >> /etc/sway/config
    fi
}

_custom_wayland_xorg() {
    if [[ -n "${_CUSTOM_WAYLAND}" ]]; then
        echo -e "\e[1mStep 1/2:\e[m Installing custom wayland..."
        echo "          This will need some time..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND}" > "${_LOG}" 2>&1
    fi
    if [[ -n "${_CUSTOM_X}" ]]; then
        echo -e "\e[1mStep 1/2:\e[m Installing custom xorg..."
        echo "          This will need some time..."
        _prepare_graphic "${_XORG_PACKAGE} ${_CUSTOM_XORG}" > "${_LOG}" 2>&1
    fi
    echo -e "\e[1mStep 2/2:\e[m Setting up browser...\e[m"
    which firefox &>"${_NO_LOG}"  && _firefox_flags
    which chromium &>"${_NO_LOG}" && _chromium_flags
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf..." >"${_LOG}"
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
archboot.com
wiki.archlinux.org
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! grep -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
            echo "Adding firefox flags vendor.js..." >"${_LOG}"
            cat << EOF >> /usr/lib/firefox/browser/defaults/preferences/vendor.js
pref("browser.aboutwelcome.enabled", false, locked);
pref("browser.startup.homepage_override.once", false, locked);
pref("datareporting.policy.firstRunURL", "https://wiki.archlinux.org", locked);
pref("browser.startup.homepage", "https://archboot.com|https://wiki.archlinux.org", locked);
pref("browser.startup.firstrunSkipsHomepage"; true, locked);
pref("startup.homepage_welcome_url", "https://archboot.com", locked );
EOF
        fi
    fi
}

_autostart_vnc() {
    echo "Setting VNC password /etc/tigervnc/passwd to ${_VNC_PW}..." >"${_LOG}"
    echo "${_VNC_PW}" | vncpasswd -f > /etc/tigervnc/passwd
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Autostarting tigervnc..." >"${_LOG}"
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
}
# vim: set ft=sh ts=4 sw=4 et:
