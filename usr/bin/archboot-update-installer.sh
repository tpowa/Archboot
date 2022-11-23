#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
#shellcheck disable=SC1094
. /usr/lib/archboot/update-installer/update-installer.sh
. /usr/lib/archboot/update-installer/xfce.sh
. /usr/lib/archboot/update-installer/gnome.sh
. /usr/lib/archboot/update-installer/gnome-wayland.sh
. /usr/lib/archboot/update-installer/plasma.sh
. /usr/lib/archboot/update-installer/plasma-wayland.sh

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
    case ${1} in
        -u|--u) _D_SCRIPTS="1" ;;
        -latest|--latest) _L_COMPLETE="1" ;;
        -latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
        -latest-image|--latest-image) _G_RELEASE="1" ;;
        -xfce|--xfce) _L_XFCE="1" ;;
        -gnome|--gnome) _L_GNOME="1";;
        -gnome-wayland|--gnome-wayland) _L_GNOME_WAYLAND="1";;
        -plasma|--plasma) _L_PLASMA="1" ;;
        -plasma-wayland|--plasma-wayland) _L_PLASMA_WAYLAND="1" ;;
        -custom-xorg|--custom-xorg) _CUSTOM_X="1" ;;
        -custom-wayland|--custom-wayland) _CUSTOM_WAYLAND="1" ;;
        -full-system) _FULL_SYSTEM="1" ;;
        -h|--h|?) usage ;;
        *) usage ;;
        esac
    shift
done

_archboot_check
_download_latest
echo -e "\033[1mInformation:\033[0m Logging is done on \033[1m/dev/tty7\033[0m ..."
_zram_initialize
# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    _new_environment
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    _new_image
fi

# install custom xorg or wayland
if [[ "${_CUSTOM_X}" == "1" || "${_CUSTOM_WAYLAND}" == "1" ]]; then
    _custom_wayland_xorg
fi

# Gnome, KDE/PLASMA or XFCE launch
if [[ "${_L_XFCE}" == "1" || "${_L_PLASMA}" == "1" || "${_L_GNOME}" == "1" || "${_L_GNOME_WAYLAND}" == "1" || "${_L_PLASMA_WAYLAND}" == "1" ]]; then
    if [[ -e "/.graphic_installed" && "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]]; then
        _hint_graphic_installed
    else
        _install_graphic
    fi
fi

# Switch to full Arch Linux system
if [[ "${_FULL_SYSTEM}" == "1" ]]; then
    _full_system
fi

