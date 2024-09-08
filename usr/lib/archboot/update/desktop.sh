#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_cleanup() {
    rm -rf /usr/share/{man,help,info,doc,gtk-doc}
    rm -rf /usr/include
    rm -rf /usr/share/icons/breeze-dark
        fd -u --min-depth 2 -E '/be/' -E '/bg/' \
             -E '/cs/' -E '/da/' -E '/de/' -E '/en/' \
             -E '/el/' -E '/es/' -E '/fi/' -E '/fr/' \
             -E '/hu/' -E '/it/' -E '/lt/' -E '/lv/' \
             -E '/mk/' -E '/nl/' -E '/nn/' -E '/pl/' \
             -E '/pt/' -E '/ro/' -E '/ru/' -E '/sk/' \
             -E '/sr/' -E '/sv/' -E '/tr/' -E '/uk/' \
             . /usr/share/locale/ -X rm &>"${_NO_LOG}"
    fd -u -t f -E 'UTF-8.gz' . /usr/share/i18n/charmaps -X rm &>"${_NO_LOG}"
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(rg -o ' (\w+) \(' -r '$1' /var/log/pacman.log); do
        rm -rf "${_CACHEDIR}/${i}"-*
    done
}

_run_pacman() {
    #shellcheck disable=2068
    for i in $@; do
        #shellcheck disable=SC2086
        LC_ALL=C.UTF-8 pacman -Sy ${i} --noconfirm &>"${_LOG}"
        if [[ ! -e "/.full_system" ]]; then
            _cleanup
        fi
        rm -f /var/log/pacman.log
    done
}

_update_packages() {
    _IGNORE=()
    #shellcheck disable=SC2128
    if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
        #shellcheck disable=SC2068
        for i in ${_GRAPHIC_IGNORE[@]}; do
            #shellcheck disable=SC2206
            _IGNORE+=(--ignore ${i})
        done
    fi
    #shellcheck disable=SC2086,SC2068
    LC_ALL=C.UTF-8 pacman -Syu ${_IGNORE[@]} --noconfirm &>"${_LOG}"
    if [[ ! -e "/.full_system" ]]; then
        _cleanup
    fi
    rm /.archboot
}

_install_fix_packages() {
    #shellcheck disable=SC2068
    _run_pacman ${_FIX_PACKAGES[@]}
    rm /.archboot
}

_install_graphic() {
    # check for qxl module
    if rg -q qxl /proc/modules; then
        _GRAPHIC+=(xf86-video-qxl)
    fi
    #shellcheck disable=SC2068
    _run_pacman ${_GRAPHIC[@]}
    rm /.archboot
}


_prepare_graphic() {
    # fix libs first, then install packages from defaults
    #shellcheck disable=SC2206
    _GRAPHIC=($@)
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

_prepare_browser() {
    if [[ "${_STANDARD_BROWSER}" == "firefox" ]]; then
        pacman -Q chromium &>"${_NO_LOG}" && pacman -R --noconfirm chromium &>"${_LOG}"
        pacman -Q firefox &>"${_NO_LOG}" || _run_pacman firefox
        # install firefox langpacks
        _LANG="be bg cs da de el fi fr hu it lt lv mk nl nn pl ro ru sk sr tr uk"
        for i in ${_LANG}; do
            if rg -q "${i}" /etc/locale.conf; then
                _run_pacman firefox-i18n-"${i}"
            fi
        done
        if rg -q en_US /etc/locale.conf; then
            _run_pacman firefox-i18n-en-us
        elif rg -q 'C.UTF-8' /etc/locale.conf; then
            _run_pacman firefox-i18n-en-us
        elif rg -q es_ES /etc/locale.conf; then
            _run_pacman firefox-i18n-es-es
        elif rg -q pt_PT /etc/locale.conf; then
            _run_pacman firefox-i18n-pt-pt
        elif rg -q sv_SE /etc/locale.conf; then
            _run_pacman firefox-i18n-sv-se
        fi
        _firefox_flags
    else
        #shellcheck disable=SC2046
        pacman -Q firefox &>"${_NO_LOG}" && pacman -R --noconfirm $(pacman -Q | rg -o 'firefox.* ') &>"${_LOG}"
        pacman -Q chromium &>"${_NO_LOG}" || _run_pacman chromium
        _chromium_flags
    fi
}

_custom_wayland_xorg() {
    if [[ -n "${_CUSTOM_WL}" ]]; then
        echo -e "\e[1mStep 1/2:\e[m Installing custom wayland..."
        echo "          This will need some time..."
        #shellcheck disable=SC2068,SC2086
        _prepare_graphic ${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND[@]} > "${_LOG}" 2>&1
    fi
    if [[ -n "${_CUSTOM_X}" ]]; then
        echo -e "\e[1mStep 1/2:\e[m Installing custom xorg..."
        echo "          This will need some time..."
        #shellcheck disable=SC2068,SC2086
        _prepare_graphic ${_XORG_PACKAGE} ${_CUSTOM_XORG[@]} > "${_LOG}" 2>&1
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
--password-store=basic
archboot.com
wiki.archlinux.org
wiki.archlinux.org/title/Installation_guide
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! rg -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
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
