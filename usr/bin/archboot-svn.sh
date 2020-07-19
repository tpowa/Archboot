#!/usr/bin/env bash
### general setup stuff
SVNSETUP="svn://svn.archlinux.org/packages/"
BASE="base linux"
DEVEL=""
SUPPORT=""
SUPPORT_ADDITION="fuse ntfs-3g dhcp f2fs-tools mtools efitools lockdown-ms gc guile libatomic_ops libaio intel-ucode unixodbc libnftnl libmnl tcl libcap-ng fuse2 fuse3 libnfnetlink libnetfilter_conntrack libcroco libxml2 python python2"
# generate base
for i in $(expac -S '%D' base); do 
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
# cleanup devel from base packages
for i in base/*; do
    [[ -d devel/$(basename $i) ]] && rm -r devel/$(basename $i)
    [[ -d support/$(basename $i) ]] && rm -r support/$(basename $i)
done
