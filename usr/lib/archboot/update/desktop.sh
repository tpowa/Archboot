#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_cleanup() {
    rm -rf /usr/share/{man,help,info,doc,gtk-doc}
    rm -rf /usr/include
    rm -rf /usr/share/icons/breeze-dark
    find /usr/share/locale/ -mindepth 2 ! -path '*/be/*' ! -path '*/bg/*' ! -path '*/cs/*' \
        ! -path '*/da/*' ! -path '*/de/*' ! -path '*/en/*' ! -path '*/el/*' ! -path '*/es/*' \
        ! -path '*/fi/*' ! -path '*/fr/*' ! -path '*/hu/*' ! -path '*/it/*' ! -path '*/lt/*' \
        ! -path '*/lv/*' ! -path '*/mk/*' ! -path '*/nl/*' ! -path '*/nn/*' ! -path '*/pl/*' \
        ! -path '*/pt/*' ! -path '*/ro/*' ! -path '*/ru/*' ! -path '*/sk/*' ! -path '*/sr/*' \
        ! -path '*/sv/*' ! -path '*/tr/*' ! -path '*/uk/*' -delete &>"${_NO_LOG}"
    find /usr/share/i18n/charmaps ! -name 'UTF-8.gz' -delete &>"${_NO_LOG}"
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(grep -w -E 'reinstalled|installed|upgraded' /var/log/pacman.log | cut -d ' ' -f 4); do
        rm -rf "${_CACHEDIR}/${i}"-[0-9]*
    done
}

_run_pacman() {
    for i in ${1}; do
        #shellcheck disable=SC2086
        LANG=C pacman -Sy ${i} --noconfirm &>"${_LOG}"
        if [[ ! -e "/.full_system" ]]; then
            _cleanup
        fi
        rm -f /var/log/pacman.log
    done
}

_update_packages() {
_IGNORE=""
    if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
        for i in ${_GRAPHIC_IGNORE}; do
            _IGNORE="${_IGNORE} --ignore ${i}"
        done
    fi
    #shellcheck disable=SC2086
    LANG=C pacman -Syu ${_IGNORE} --noconfirm &>"${_LOG}"
    if [[ ! -e "/.full_system" ]]; then
        _cleanup
    fi
    rm /.archboot
}

_install_fix_packages() {
    _run_pacman "${_FIX_PACKAGES}"
    rm /.archboot
}

_install_graphic() {
    # check for qxl module
    if grep -q qxl /proc/modules; then
        _GRAPHIC="${_GRAPHIC} xf86-video-qxl"
    fi
    _run_pacman "${_GRAPHIC}"
    # install firefox langpacks
    if [[ "${_STANDARD_BROWSER}" == "firefox" ]]; then
        _LANG="be bg cs da de el fi fr hu it lt lv mk nl nn pl ro ru sk sr tr uk"
        for i in ${_LANG}; do
            if grep -q "${i}" /etc/locale.conf; then
                _run_pacman firefox-i18n-"${i}"
            fi
        done
        if grep -q en_US /etc/locale.conf; then
            _run_pacman firefox-i18n-en-us
        elif grep -q 'C.UTF-8' /etc/locale.conf; then
            _run_pacman firefox-i18n-en-us
        elif grep -q es_ES /etc/locale.conf; then
            _run_pacman firefox-i18n-es-es
        elif grep -q pt_PT /etc/locale.conf; then
            _run_pacman firefox-i18n-pt-pt
        elif grep -q sv_SE /etc/locale.conf; then
            _run_pacman firefox-i18n-sv-se
        fi
    fi
    rm /.archboot
}

_prepare_graphic() {
    # fix libs first, then install packages from defaults
    _GRAPHIC="${1}"
    if [[ ! -e "/.full_system" ]]; then
        _progress "1" "Removing firmware files..."
        rm -rf /usr/lib/firmware
    fi
    : > /.archboot
    _update_packages &
    _progress_wait "2" "10" "Updating environment to latest packages..." "5"
    : > /.archboot
    _install_fix_packages &
    _progress_wait "${_COUNT}" "20" "Installing basic packages..." "3"
    : > /.archboot
    _install_graphic &
    _progress_wait "${_COUNT}" "97" "Installing ${_ENVIRONMENT}..." "3"
    _progress "98" "Restart dbus..."
    systemd-sysusers >"${_LOG}" 2>&1
    # add --boot to really create all tmpfiles!
    # Check: /tmp/.X11-unix, may have wrong permission on startup error!
    systemd-tmpfiles --boot --create >"${_LOG}" 2>&1
    # fixing dbus requirements
    for i in dbus dbus-org.freedesktop.login1.service; do
        systemctl reload ${i}
    done
    # start polkit, most desktop environments expect it running!
    systemctl restart polkit
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
    command -v firefox &>"${_NO_LOG}"  && _firefox_flags
    command -v chromium &>"${_NO_LOG}" && _chromium_flags
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf..." >"${_LOG}"
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
archboot.com
wiki.archlinux.org
wiki.archlinux.org/title/Installation_guide
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! grep -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
            echo "Adding firefox flags vendor.js..." >"${_LOG}"
            cat << EOF >> /usr/lib/firefox/browser/defaults/preferences/vendor.js
pref("browser.aboutwelcome.enabled", false, locked);
pref("browser.startup.homepage_override.once", false, locked);
pref("datareporting.policy.firstRunURL", "https://wiki.archlinux.org/title/Installation_guide", locked);
pref("browser.startup.homepage", "https://archboot.com|https://wiki.archlinux.org|https://wiki.archlinux.org/title/Installation_guide", locked);
pref("browser.startup.firstrunSkipsHomepage"; true, locked);
pref("startup.homepage_welcome_url", "https://archboot.com|https://wiki.archlinux.org", locked );
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
