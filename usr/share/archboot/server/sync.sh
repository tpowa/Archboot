#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
if [[ -e ~/.rsync-running ]]; then
    echo "ERROR: rsync is already running!"
    exit 1
else
    : > .rsync-running
    echo "Syncing files to U.S. mirror: archboot.org..."
    rsync -a -q --delete --delete-delay pkg src iso archboot.org:public_html
    rm .rsync-running
fi
# vim: set ft=sh ts=4 sw=4 et:
