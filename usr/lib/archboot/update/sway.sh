#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_configure_sway() {
    echo "Configuring Sway..."
    echo "Configuring bemenu..."
    #shellcheck disable=SC2016
    sed -i -e 's|^set $menu.*|set $menu j4-dmenu-desktop --dmenu=\x27bemenu -i --tf "#00ff00" --hf "#00ff00" --nf "#dcdccc" --fn "pango:Terminus 12" -H 30\x27 --no-generic --term="foot"|g' /etc/sway/config
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
        [[ -f /usr/share/applications/"${i}".desktop ]] || break
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

_install_sway() {
    _PACKAGES="${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_SWAY_PACKAGES}"
    if ! [[ -e /usr/bin/sway ]]; then
        _prepare_graphic "${_PACKAGES}"
        _configure_sway >"${_LOG}" 2>&1
    fi
}

_start_sway() {
    echo "MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland \
        XKB_DEFAULT_LAYOUT=$(grep 'KEYMAP' /etc/vconsole.conf | cut -d '=' -f2 | sed -e 's#-.*##g') \
        exec dbus-run-session sway >${_LOG} 2>&1" > /usr/bin/sway-wayland
    chmod 755 /usr/bin/sway-wayland
    sway-wayland
}
# vim: set ft=sh ts=4 sw=4 et:
