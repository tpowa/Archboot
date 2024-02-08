#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

# ask for bcachefs compress option
_bcachefs_compress() {
    _BCACHEFS_COMPRESSLEVELS="zstd - lz4 - gzip - NONE -"
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " Compression on ${_DEV} " --menu "" 10 50 4 ${_BCACHEFS_COMPRESSLEVELS} 2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "NONE" ]]; then
        _BCACHEFS_COMPRESS="NONE"
    else
        _BCACHEFS_COMPRESS="$(cat "${_ANSWER}")"
    fi
}
