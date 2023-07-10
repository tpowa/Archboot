#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
#shellcheck disable=SC1094
. /usr/lib/archboot/update/update.sh
. /usr/lib/archboot/update/xfce.sh
. /usr/lib/archboot/update/gnome.sh
. /usr/lib/archboot/update/gnome-wayland.sh
. /usr/lib/archboot/update/plasma.sh
. /usr/lib/archboot/update/plasma-wayland.sh
[[ -z "${1}" ]] && usage
while [ $# -gt 0 ]; do
    case ${1} in
        -u|--u|-update|--update) _D_SCRIPTS="1" ;;
        -latest|--latest) _L_COMPLETE="1" ;;
        -latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
        -latest-image|--latest-image) _G_RELEASE="1" ;;
        -xfce|--xfce) _L_XFCE="1" ;;
        -sway|--sway) _L_SWAY="1" ;;
        -gnome|--gnome) _L_GNOME="1";;
        -gnome-wayland|--gnome-wayland) _L_GNOME_WAYLAND="1";;
        -plasma|--plasma) _L_PLASMA="1" ;;
        -plasma-wayland|--plasma-wayland) _L_PLASMA_WAYLAND="1" ;;
        -custom-xorg|--custom-xorg) _CUSTOM_X="1" ;;
        -custom-wayland|--custom-wayland) _CUSTOM_WAYLAND="1" ;;
        -full-system|--full-system) _FULL_SYSTEM="1" ;;
        -h|--h|-help|--help|?) usage ;;
        *) usage ;;
        esac
    shift
done
_archboot_check
_download_latest
echo -e "\e[1mInformation:\e[m Logging is done on \e[1m/dev/tty7\e[m..."
# Generate new environment and launch it with kexec
if [[ -n "${_L_COMPLETE}" || -n "${_L_INSTALL_COMPLETE}" ]]; then
    _new_environment
fi
# Generate new images
if [[ -n "${_G_RELEASE}" ]]; then
    _new_image
fi
# install custom xorg or wayland
if [[ -n "${_CUSTOM_X}" || -n "${_CUSTOM_WAYLAND}" ]]; then
    _custom_wayland_xorg
fi
# Gnome, KDE/PLASMA or XFCE launch
if [[ -n "${_L_XFCE}" || -n "${_L_PLASMA}" || -n "${_L_GNOME}" || -n "${_L_GNOME_WAYLAND}" || -n "${_L_PLASMA_WAYLAND}" ]]; then
    if [[ -e "/.graphic_installed" && "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]]; then
        _hint_graphic_installed
    else
        _install_graphic
    fi
fi
# Switch to full Arch Linux system
if [[ -n "${_FULL_SYSTEM}" ]]; then
    _full_system
fi
