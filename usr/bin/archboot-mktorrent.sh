#!/usr/bin/env bash

# install mktorrent from http://mktorrent.sourceforge.net/
# check result on e.g. http://torrenteditor.com/

if [ "${1}" = "" -o "${2}" = "" ]; then
	echo "Usage: ${0} <version> <iso file>"
	echo -e "\tversion:\te.g. 2009.05 or archboot/2009.05"
	echo -e "\tiso file:\te.g. ./archlinux-2009.05-core-x86_64.iso"
	exit 1
fi

archver="${1}"
isofile="${2}"

echo 'Creating webseeds...'
httpmirrorlist=$(wget http://www.archlinux.org/mirrorlist/all/http/ -q -O - \
	- | grep 'http://' \
	| awk "{print \$3\"/iso/${archver}/\";}" \
	| sed -e 's#/$repo/os/$arch##' \
	      -e 's#\s*# -w #')

echo 'Building torrent...'
mktorrent \
	-l 19 \
	-a 'http://tracker.archlinux.org:6969/announce' \
        -a 'http://linuxtracker.org:2710/announce' \
	-c "Arch Linux ${archver} (www.archlinux.org)" \
	${httpmirrorlist} \
	"${isofile}"
