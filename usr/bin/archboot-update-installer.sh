#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

# Download latest setup and quickinst script from git repository

echo 'Downloading latest quickinst and setup script...'
INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/bin"
[[ -e /arch/quickinst ]] && wget -q "$INSTALLER_SOURCE/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst
[[ -e /arch/setup ]] && wget -q "$INSTALLER_SOURCE/archboot-setup.sh?inline=false" -O /usr/bin/setup

