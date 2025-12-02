#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Created by Tobias Powalowski <tpowa@archlinux.org>
magick ../grub/archboot-background.png -white-threshold 50% -monochrome archboot-background-mono.bmp
magick archboot-background-mono.bmp -fill '#0189FD' -opaque white -colors 2 archboot-background-blue.bmp
magick archboot-background-blue.bmp -fill black -opaque white -colors 2 archboot-background.bmp
rm archboot-background-{mono,blue}.bmp
magick ../grub/archboot-background.png -alpha off -white-threshold 50% -fill '#0189FD' -opaque white ../grub/archboot-background.png
