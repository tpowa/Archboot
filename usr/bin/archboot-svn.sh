#!/bin/sh
### general setup stuff
SVNSETUP="svn://svn.archlinux.org/packages/"
BASE=""
DEVEL=""
SUPPORT=""
SUPPORT_ADDITION="dmidecode gnu-netcat dosfstools ntfs-3g_ntfsprogs fuse dhcp v86d grub f2fs-tools"
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
cd base; for i in $BASE; do svn up $i; sleep 2; done; cd ..
cd devel; for i in $DEVEL; do svn up $i; sleep 2; done;  cd ..
cd support; for i in $SUPPORT; do svn up $i; sleep 2; done; cd ..
