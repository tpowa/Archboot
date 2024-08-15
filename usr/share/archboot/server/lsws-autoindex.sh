#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

# copy header and footer for autoindex litespeed webserver
# header is placed in plain text on top
# readme is placed in plain text on bottom
# main site
for i in pkg release src; do
    #shellcheck disable=SC2044
    for k in $(find public_html/"${i}"/ -type d); do
        [[ "${i}" == "release" ]] && _TITLE="Release Mirror"
        [[ "${i}" == "pkg" ]] && _TITLE="Package Repository"
        [[ "${i}" == "src" ]] && _TITLE="Sources"
        echo "Archboot - ${_TITLE} | (c) 2006 - $(date +%Y) Tobias Powalowski | Arch Linux Developer tpowa" > "${k}"/HEADER.html
    done
done
# mirrors
# clean and create directories
rm ~/release/* 2>/dev/null
for i in aarch64 riscv64 x86_64; do
    [[ -d ~/release/"${i}" ]] || mkdir -p ~/release/"${i}"
    rm ~/release/"${i}"/*
done
# create html on mirrors
for i in ./{,aarch64,riscv64,x86_64}; do
    ln -s ~/public_html/release/"${i}"/HEADER.html \
          ~/release/"${i}"/HEADER.html
done
# keep 4 versions on mirrors
for i in $(seq 0 3); do
    _SYMLINK=$(date -d "$(date +) - ${i} Months" +%Y.%m)
    for k in aarch64 riscv64 x86_64; do
        if [[ -d ~/public_html/release/"${k}"/"${_SYMLINK}" && ! -L ~/release/"${k}"/"${_SYMLINK}" ]]; then
            ln -s ~/public_html/release/"${k}"/"${_SYMLINK}" \
                  ~/release/"${k}"/"${_SYMLINK}"
        fi
    done
done
