#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

# Download latest setup and quickinst script from git repository

echo 'Downloading latest quickinst and setup script...'
INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/share/archboot/installer/"
[[ -e /arch/quickinst ]] && wget -q "$INSTALLER_SOURCE/quickinst?inline=false" -O /arch/quickinst
[[ -e /arch/setup ]] && wget -q "$INSTALLER_SOURCE/setup?inline=false" -O /arch/setup

