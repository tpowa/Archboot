#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

# copy header and footer for autoindex litespeed webserver
# header is placed in plain text on top
# readme is placed in plain text on bottom
for i in pkg release src; do
    for k in $(find public_html/${i}/ -type d); do
        [[ "${i}" == "release" ]] && _TITLE="CDN Release Mirror"
        [[ "${i}" == "pkg" ]] && _TITLE="Package Repository"
        [[ "${i}" == "src" ]] && _TITLE="Sources"
        echo "Archboot - ${_TITLE} | (c) 2006 - $(date +%Y) Tobias Powalowski | Arch Linux Developer tpowa" > ${k}/HEADER.html
    done
done
# vim: set ft=sh ts=4 sw=4 et:
