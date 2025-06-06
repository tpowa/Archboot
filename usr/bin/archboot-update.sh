#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/update/update.sh
. /usr/lib/archboot/update/manage.sh
. /usr/lib/archboot/update/desktop.sh
. /usr/lib/archboot/update/xfce.sh
. /usr/lib/archboot/update/gnome.sh
. /usr/lib/archboot/update/plasma.sh
. /usr/lib/archboot/update/sway.sh

[[ -z "${1}" ]] && _usage
while [ $# -gt 0 ]; do
    case ${1} in
        -u|--u|-update|--update) _D_SCRIPTS="1" ;;
        -latest|--latest) _L_COMPLETE="1" ;;
        -latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
        -latest-image|--latest-image) _G_RELEASE="1"
                                      _L_INSTALL_COMPLETE="1";;
        -xfce|--xfce) _L_XFCE="1" ;;
        -sway|--sway) _L_SWAY="1" ;;
        -gnome|--gnome) _L_GNOME="1";;
        -plasma|--plasma) _L_PLASMA="1" ;;
        -custom-xorg|--custom-xorg) _CUSTOM_X="1" ;;
        -custom-wayland|--custom-wayland) _CUSTOM_WL="1" ;;
        -full-system|--full-system) _FULL_SYSTEM="1" ;;
        -h|--h|-help|--help|?) _usage ;;
        *) _usage ;;
        esac
    shift
done
_archboot_check
if [[ -n "${_D_SCRIPTS}" ]]; then
    _update_installer_check
    _network_check
    : > /.update
    _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | GIT Master Scripts"
    _download_latest | _dialog --title " Archboot GIT Master " --gauge "Downloading latest GIT..." 6 75 0
    clear
fi
# Generate new environment and launch it with kexec
if [[ -n "${_L_COMPLETE}" || -n "${_L_INSTALL_COMPLETE}" ]] && [[ -z "${_G_RELEASE}" ]]; then
    _update_installer_check
    _geoip_mirrorlist
    : > /.update
    _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | New Environment"
    _new_environment | _dialog --title "${_MENU_TITLE}" --gauge "Waiting for pacman keyring..." 6 75 0
    clear
fi
# Generate new images
if [[ -n "${_G_RELEASE}" ]]; then
    _update_installer_check
    : > /.update
    _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | New Images"
    _new_image | _dialog --title "${_MENU_TITLE}" --gauge "Removing not necessary files from /..." 6 75 0
    clear
fi
# install custom xorg or wayland
if [[ -n "${_CUSTOM_X}" || -n "${_CUSTOM_WL}" ]]; then
    _custom_wayland_xorg
fi
# Gnome, KDE/PLASMA or XFCE launch
if [[ -n "${_L_XFCE}" || -n "${_L_SWAY}" || -n "${_L_PLASMA}" || -n "${_L_GNOME}" ]]; then
    : > /.update
    _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Desktop Environment"
    [[ -e /var/cache/pacman/pkg/archboot.db ]] && : > /.graphic_installed
    if [[ -n "${_L_XFCE}" ]]; then
        _ENVIRONMENT="XFCE"
        _install_xfce | _dialog --title "${_MENU_TITLE}" --gauge "Initializing ${_ENVIRONMENT}..." 6 75 0
    elif [[ -n "${_L_GNOME}" ]]; then
        _ENVIRONMENT="GNOME"
        _install_gnome | _dialog --title "${_MENU_TITLE}" --gauge "Initializing ${_ENVIRONMENT}..." 6 75 0
    elif [[ -n "${_L_PLASMA}" ]];then
        _ENVIRONMENT="Plasma/KDE"
        _install_plasma | _dialog --title "${_MENU_TITLE}" --gauge "Initializing ${_ENVIRONMENT}..." 6 75 0
    elif [[ -n "${_L_SWAY}" ]]; then
        _ENVIRONMENT="Sway"
        _install_sway | _dialog --title "${_MENU_TITLE}" --gauge "Initializing ${_ENVIRONMENT}..." 6 75 0
    fi
    rm /.update
    # only start vnc on xorg environment
    echo "Setting up VNC and browser..." >"${_LOG}"
    [[ -n "${_L_XFCE}" ]] && _autostart_vnc
    echo "Setting ${_STANDARD_BROWSER} as default browser..." >"${_LOG}"
    # gnome
    if command -v gsettings &>"${_NO_LOG}"; then
        [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
        [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    fi
    # plasma and xfce
    sd 'firefox' "${_STANDARD_BROWSER}" /etc/xdg/xfce4/helpers.rc \
        /etc/xdg/menus/plasma-applications.menu \
        /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml 2>"${_NO_LOG}"
    sd 'chromium' "${_STANDARD_BROWSER}" /etc/xdg/xfce4/helpers.rc \
        /etc/xdg/menus/plasma-applications.menu \
        /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml 2>"${_NO_LOG}"
    if [[ -n "${_L_XFCE}" ]]; then
        _start_xfce | _dialog --title "${_MENU_TITLE}" --gauge "Starting ${_ENVIRONMENT}..." 6 75 99
        clear
        echo -e "To relaunch \e[1mXFCE\e[m desktop use: \e[92mstartxfce4\e[m"
    elif [[ -n "${_L_GNOME}" ]]; then
        _start_gnome | _dialog --title "${_MENU_TITLE}" --gauge "Starting ${_ENVIRONMENT}..." 6 75 99
        clear
        echo -e "To relaunch \e[1mGNOME Wayland\e[m use: \e[92mgnome-wayland\e[m"
    elif [[ -n "${_L_PLASMA}" ]]; then
        _start_plasma | _dialog --title "${_MENU_TITLE}" --gauge "Starting ${_ENVIRONMENT}..." 6 75 99
        clear
        echo -e "To relaunch \e[1mKDE/Plasma Wayland\e[m use: \e[92mplasma-wayland\e[m"
    elif [[ -n "${_L_SWAY}" ]]; then
        _start_sway | _dialog --title "${_MENU_TITLE}" --gauge "Starting ${_ENVIRONMENT}..." 6 75 99
        clear
        echo -e "To relaunch \e[1mSway\e[m use: \e[92msway-wayland\e[m"
    fi
fi
# Switch to full Arch Linux system
if [[ -n "${_FULL_SYSTEM}" ]]; then
    _full_system_check
    _update_installer_check
    : > /.update
    _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Full System"
    _full_system | _dialog --title "${_MENU_TITLE}" --gauge "Refreshing pacman package database..." 6 75 0
    clear
fi
[[ -e /.update ]] && rm /.update
