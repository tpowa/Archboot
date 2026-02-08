#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_FAVORITES=/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites

_configure_cosmic() {
    echo "Configuring Cosmic..."
    _HIDE_MENU="avahi-discover bssh bvnc qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        if [[ -f /usr/share/applications/"${i}".desktop ]]; then
            echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
            echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
        fi
    done
    if ! [[ -d /root/.config/cosmic ]]; then
        echo "Configuring wallpaper..."
    sd "/usr/share/backgrounds/cosmic/orion_nebula_nasa_heic0601a.jpg" \
       "/usr/share/archboot/grub/archboot-background.png"  \
       /usr/share/cosmic/com.system76.CosmicBackground/v1/all
        # modify dock
        echo "Configuring dock..."
        sd 'false' 'true' /usr/share/cosmic/com.system76.CosmicPanel.Dock/v1/expand_to_edges
        sd 'L' 'S' /usr/share/cosmic/com.system76.CosmicPanel.Dock/v1/size
        sd '"com.system76.CosmicPanelLauncherButton", "com.system76.CosmicPanelWorkspacesButton", "com.system76.CosmicPanelAppButton", ' '' \
            /usr/share/cosmic/com.system76.CosmicPanel.Dock/v1/plugins_center
        sd 'com.system76.CosmicSettings' 'archboot' ${_FAVORITES}
        sd 'firefox' 'com.system76.CosmicSettings' ${_FAVORITES}
        sd 'com.system76.CosmicTerm' 'gparted' ${_FAVORITES}
        sd 'com.system76.CosmicFiles' 'com.system76.CosmicTerm' ${_FAVORITES}
        sd 'com.system76.CosmicEdit' 'com.system76.CosmicFiles' ${_FAVORITES}
        sd 'com.system76.CosmicStore' "${_STANDARD_BROWSER}" ${_FAVORITES}
    fi
    echo "Autostarting setup..."
    cat << EOF > /usr/share/applications/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=cosmic-term -- /usr/bin/setup
Icon=system-software-install
EOF
}

_install_cosmic() {
    if ! [[ -e /usr/bin/start-cosmic ]]; then
        _prepare_graphic "${_STANDARD_PACKAGES[@]}" "${_COSMIC_PACKAGES[@]}"
    fi
    _prepare_browser &>>"${_LOG}"
    _configure_cosmic &>>"${_LOG}"
}

_start_cosmic() {
    _progress "100" "Launching Cosmic now, logging is done on ${_LOG}..."
    sleep 2
    # list available layouts:
    # localectl list-x11-keymap-layouts
    _KEYMAP=$(rg -o '^KEYMAP=(\w+)' -r '$1' /etc/vconsole.conf)
    [[ -z ${_KEYMAP} ]] && _KEYMAP=us
    echo \
"export XKB_DEFAULT_LAYOUT=${_KEYMAP}
exec kmscon-launch-gui start-cosmic" \
         > /usr/bin/cosmic-wayland
    chmod 755 /usr/bin/cosmic-wayland
    mkdir -p /root/.local/state
    mkdir -p /root/Desktop
    systemctl restart upower acpid
}
