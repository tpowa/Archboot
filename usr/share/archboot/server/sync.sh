#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_SYNC_SERVER="archboot.org archboot.net"
for i in ${_SYNC_SERVER}; do
    if [[ -e ~/.rsync-running ]]; then
        echo "ERROR: rsync is already running!"
        exit 1
    else
        : > .rsync-running
        echo "Syncing files to mirror: ${i}..."
        rsync -a -q --delete --delete-delay pkg src iso ${i}:public_html/
        rm .rsync-running
    fi
done
# vim: set ft=sh ts=4 sw=4 et:
