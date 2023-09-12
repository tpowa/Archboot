#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

# copy header and footer for autoindex litespeed webserver
# header is placed in plain text on top
# readme is placed in plain text on bottom
for i in $(find public_html/*/ -type d); do
	cp lsws-header.html ${i}/HEADER.html
	cp lsws-readme.html ${i}/README.html
done
# vim: set ft=sh ts=4 sw=4 et:
