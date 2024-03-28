#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

# copy header and footer for autoindex litespeed webserver
# header is placed in plain text on top
# readme is placed in plain text on bottom
# main site
for i in pkg release src; do
    for k in $(find public_html/${i}/ -type d); do
        [[ "${i}" == "release" ]] && _TITLE="Release Mirror"
        [[ "${i}" == "pkg" ]] && _TITLE="Package Repository"
        [[ "${i}" == "src" ]] && _TITLE="Sources"
        echo "Archboot - ${_TITLE} | (c) 2006 - $(date +%Y) Tobias Powalowski | Arch Linux Developer tpowa" > ${k}/HEADER.html
    done
done
# mirrors
cd public_html
for k in $(find release/ -type d); do
    _TITLE="Release Mirror"
    [[ -d "~/${k}" ]] && echo "Archboot - ${_TITLE} | (c) 2006 - $(date +%Y) Tobias Powalowski | Arch Linux Developer tpowa" 2>/dev/null > ~/${k}/HEADER.html
done
# clean directory first
for i in aarch64 riscv64 x86_64; do
    rm ~/release/${i}/*
done
# keep 4 versions on mirrors
for i in $(seq 0 3); do 
    _SYMLINK=$(date -d "$(date +) - ${i} Months" +%Y.%m)
    for k in aarch64 riscv64 x86_64; do
        ln -s ~/public_html/release/${k}/${_SYMLINK} \
              ~/release/${k}/${_SYMLINK}
    done
done
# vim: set ft=sh ts=4 sw=4 et:
