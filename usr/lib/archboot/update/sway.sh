#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_configure_sway() {
    echo "Configuring Sway..."
    echo "Configuring bemenu..."
    #shellcheck disable=SC2016
    sd '^set \$menu.*' 'set $$menu j4-dmenu-desktop --dmenu=\x27bemenu -i --tf "#00ff00" --hf "#00ff00" --nf "#dcdccc" --fn "pango:Terminus 12" -H 30\x27 --no-generic --term="foot"' \
    /etc/sway/config
    echo "Configuring wallpaper..."
    sd '^output .*' 'output * bg /usr/share/archboot/grub/archboot-background.png fill' /etc/sway/config
    echo "Configuring foot..."
    if ! rg -q 'archboot colors' /etc/xdg/foot/foot.ini; then
cat <<EOF >> /etc/xdg/foot/foot.ini
# Archboot colors
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
    rg -q 'exec foot' /etc/sway/config ||\
        echo "exec foot -- /usr/bin/setup" >> /etc/sway/config
    if ! rg -q firefox /etc/sway/config; then
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
    _HIDE_MENU="avahi-discover bssh bvnc fluid foot-server footclient lstopo qvidcap qv4l2 vncviewer"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        if [[ -f /usr/share/applications/"${i}".desktop ]]; then
            echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
            echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
        fi
    done
    echo "Configuring waybar..."
    if ! rg -q 'exec waybar' /etc/sway/config; then
        # hide sway-bar
        sd 'position top' 'a mode invisible' /etc/sway/config
        # diable not usable plugins
        echo "exec waybar" >> /etc/sway/config
        for i in custom/{media,power} mpd idle_inhibitor pulseaudio; do
            sd "$i" '' /etc/xdg/waybar/config.jsonc
        done
    fi
    echo "Configuring wayvnc..."
     if ! rg -q wayvnc /etc/sway/config; then
        echo "address=0.0.0.0" > /etc/wayvnc
        echo "exec wayvnc -C /etc/wayvnc &" >> /etc/sway/config
    fi
}

_install_sway() {
    if ! [[ -e /usr/bin/sway ]]; then
        _prepare_graphic "${_STANDARD_PACKAGES[@]}" "${_SWAY_PACKAGES[@]}"
    fi
    _prepare_browser &>>"${_LOG}"
    _configure_sway &>>"${_LOG}"
}

_start_sway() {
    _progress "100" "Launching Sway now, logging is done on ${_LOG}..."
    sleep 2
    # list available layouts:
    # localectl list-x11-keymap-layouts
    _KEYMAP=$(rg -o '^KEYMAP=(\w+)' -r '$1' /etc/vconsole.conf)
    [[ -z ${_KEYMAP} ]] && _KEYMAP=us
    echo "export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export XKB_DEFAULT_LAYOUT=${_KEYMAP}
exec kmscon-launch-gui sway" > /usr/bin/sway-wayland
    chmod 755 /usr/bin/sway-wayland
}
