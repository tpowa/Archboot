#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Created by Tobias Powalowski <tpowa@archlinux.org>
magick ../grub/archboot-background.png -white-threshold 50% -monochrome archboot-background-mono.bmp
magick archboot-background-mono.bmp -fill '#0189FD' -opaque black -colors 2 archboot-background-blue.bmp
magick archboot-background-blue.bmp -fill black -opaque white -colors 2 archboot-background.bmp
rm archboot-background-{mono,blue}.bmp

