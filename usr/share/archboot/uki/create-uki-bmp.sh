#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Created by Tobias Powalowski <tpowa@archlinux.org>
magick ../grub/archboot-background.png -monochrome archboot-background-mono.bmp
magick archboot-background-mono.bmp -fill '#0189FD' -opaque white  -colors 2 archboot-background.bmp
rm archboot-background-mono.bmp

