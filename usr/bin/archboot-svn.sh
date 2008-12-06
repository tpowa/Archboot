#!/bin/sh
### general setup stuff
SVNSETUP="svn://archlinux.org/srv/svn-packages/"
# generate base
BASE=""
for i in $(pacman -Sg base | sed -e "s/base//g"); do 
	BASE="$BASE $(echo $i)"
done
# generate base-devel
DEVEL=""
for i in $(pacman -Sg base-devel | sed -e "s/base-devel//g"); do 
	DEVEL="$DEVEL $(echo $i)"
done
SUPPORT="$(echo -n $(pacman -Ss | grep -e ^core | grep -v '(' | sed -e 's/\ .*/ /g' -e 's#core/##g'))"
for i in base devel support; do
    mkdir $i
    svn co -N ${SVNSETUP} $i
done
cd base; svn up $BASE; cd ..
cd devel; svn up $DEVEL; cd ..
cd support; svn up $SUPPORT; cd .. 
