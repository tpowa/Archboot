#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_install_xfce() {
    if ! [[ -e /usr/bin/startxfce4 ]]; then
        _prepare_graphic "${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_XFCE_PACKAGES}"
    fi
    _prepare_browser
    _configure_xfce  >"${_LOG}" 2>&1
}

_configure_xfce() {
    echo "Configuring xfce panel..."
    cat << EOF >/etc/xdg/xfce4/panel/default.xml
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="16"/>
      <property name="size" type="uint" value="26"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
      </property>
    </property>
    <property name="panel-2" type="empty">
      <property name="autohide-behavior" type="uint" value="1"/>
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="1"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="48"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="15"/>
        <value type="int" value="16"/>
        <value type="int" value="17"/>
        <value type="int" value="18"/>
        <value type="int" value="19"/>
        <value type="int" value="20"/>
        <value type="int" value="21"/>
        <value type="int" value="22"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="pager"/>
    <property name="plugin-5" type="string" value="separator">
        <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-6" type="string" value="systray">
        <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-8" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="true"/>
    </property>
    <property name="plugin-9" type="string" value="power-manager-plugin"/>
    <property name="plugin-10" type="string" value="notification-plugin"/>
    <property name="plugin-11" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-12" type="string" value="clock"/>
    <property name="plugin-13" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-14" type="string" value="actions"/>
    <property name="plugin-15" type="string" value="showdesktop"/>
    <property name="plugin-16" type="string" value="separator"/>
    <property name="plugin-17" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-terminal-emulator.desktop"/>
      </property>
    </property>
    <property name="plugin-18" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-file-manager.desktop"/>
      </property>
    </property>
    <property name="plugin-19" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-web-browser.desktop"/>
      </property>
    </property>
    <property name="plugin-20" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="gparted.desktop"/>
      </property>
    </property>
    <property name="plugin-21" type="string" value="separator"/>
    <property name="plugin-22" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="archboot.desktop"/>
      </property>
    </property>
  </property>
</channel>
EOF
    echo "Setting breeze as default icons..."
    sed -i -e 's#<property name="IconThemeName" type="string" value="Adwaita"/>#<property name="IconThemeName" type="string" value="breeze"/>#g' \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
    echo "Setting archboot background image..."
    cat << EOF >/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="last-single-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        <property name="image-show" type="bool" value="true"/>
        <property name="image-style" type="int" value="0"/>
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
      <property name="monitorHDMI1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="3"/>
          <property name="last-image" type="string" value="/usr/share/archboot/grub/archboot-background.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
    echo "Replacing appfinder launcher with gparted..."
    sed -i -e 's#xfce4-appfinder#gparted#g' /etc/xdg/xfce4/panel/default.xml
    echo "Replacing directory menu launcher with setup..."
    sed -i -e 's#directorymenu#archboot#g' /etc/xdg/xfce4/panel/default.xml
    echo "Replacing menu structure..."
    cat << EOF >/etc/xdg/menus/xfce-applications.menu
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
    <Name>Xfce</Name>

    <DefaultAppDirs/>
    <DefaultDirectoryDirs/>

    <Include>
        <Category>X-Xfce-Toplevel</Category>
    </Include>

    <Layout>
	<Filename>archboot.desktop</Filename>
        <Filename>gparted.desktop</Filename>
        <Filename>xfce4-run.desktop</Filename>
        <Separator/>
        <Filename>xfce4-terminal-emulator.desktop</Filename>
        <Filename>xfce4-file-manager.desktop</Filename>
	<Filename>xfce4-web-browser.desktop</Filename>
        <Separator/>
        <Menuname>Settings</Menuname>
        <Separator/>
        <Merge type="all"/>
        <Separator/>
        <Filename>xfce4-session-logout.desktop</Filename>
    </Layout>

    <Menu>
        <Name>Settings</Name>
        <Directory>xfce-settings.directory</Directory>
        <Include>
            <Category>Settings</Category>
        </Include>

        <Layout>
            <Filename>xfce-settings-manager.desktop</Filename>
            <Separator/>
            <Merge type="all"/>
        </Layout>

        <Menu>
            <Name>Screensavers</Name>
            <Directory>xfce-screensavers.directory</Directory>
            <Include>
                <Category>Screensaver</Category>
            </Include>
        </Menu>
    </Menu>

    <DefaultMergeDirs/>

</Menu>
EOF
    echo "Adding gparted to xfce top level menu..."
    sed -i -e 's#Categories=.*#Categories=X-Xfce-Toplevel;#g' /usr/share/applications/gparted.desktop
    _HIDE_MENU="xfce4-mail-reader xfce4-about"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        if [[ -f /usr/share/applications/"${i}".desktop ]]; then
          echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
        fi
    done
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=xfce4-terminal -x /usr/bin/setup
Icon=system-software-install
Categories=X-Xfce-Toplevel;
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_start_xfce() {
    _progress "100" "Launching XFCE now, logging is done on ${_LOG}..."
    sleep 2
    startxfce4 >"${_LOG}" 2>&1
}
# vim: set ft=sh ts=4 sw=4 et:
