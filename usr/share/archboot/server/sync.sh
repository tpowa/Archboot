#!/bin/bash
if [[ -e ~/.rsync-running ]]; then
	echo "ERROR: rsync is already running!"
	exit 1
else
	: > .rsync-running
	echo "Syncing files to U.S. mirror: archboot.org..."
	rsync -a -q --delete --delete-delay pkg src iso archboot.org:public_html
	rm .rsync-running
fi
