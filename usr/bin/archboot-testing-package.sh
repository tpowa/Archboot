#! /bin/sh
PACKAGES=""
for i in $PACKAGES; do
	k=$(find ./ -type d -name $i)
        if [ -d $k/repos/core-$(uname -m) ]; then
		cp $k/trunk/PKGBUILD $k/repos/core-$(uname -m)/ || echo $i
	elif [ -d $k/repos/core-any ]; then
		cp $k/trunk/PKGBUILD $k/repos/core-any/ || echo $i
	fi
done
