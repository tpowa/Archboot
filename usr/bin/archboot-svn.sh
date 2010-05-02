#!/bin/sh
### general setup stuff
SVNSETUP="svn://svn.archlinux.org/packages/"
BASE=""
DEVEL=""
SUPPORT=""
SUPPORT_ADDITION="gnu-netcat ntfs-3g fuse dhclient nouveau-drm nouveau-firmware v86d"
# generate base
for i in $(pacman -Sg base | sed -e "s/base//g"); do 
	BASE="$BASE $(echo $i)"
done
# generate base-devel
for i in $(pacman -Sg base-devel | sed -e "s/base-devel//g"); do 
	DEVEL="$DEVEL $(echo $i)"
done
# generate support, ntfs-3g is added additionally!
SUPPORT="$(echo -n $(pacman -Ss | grep -e ^core | grep -v '(' | sed -e 's/\ .*/ /g' -e 's#core/##g')) $SUPPORT_ADDITION"
for i in base devel support; do
    mkdir $i
    svn co -N ${SVNSETUP} $i
done
cd base; svn up $BASE; cd ..
cd devel; svn up $DEVEL; cd ..
cd support; svn up $SUPPORT; cd .. 
