#! /bin/sh
ARCH="$(uname -m)"
NAME="$(date +%Y%m%d)"
mkdir iso-creator-$ARCH
cd iso-creator-$ARCH
mkbootcd -c=/etc/archboot/archbootcd.conf -t=$NAME-$ARCH.tar.bz2
mkbootcd -c=/etc/archboot/archbootcd-tarball.conf -t=$NAME-$ARCH-lowmem.tar.bz2
mkdir normal
mkdir lowmem
tar xvfj $NAME-$ARCH.tar.bz2
mv tmp normal/
tar xvfj $NAME-$ARCH-lowmem.tar.bz2
mv tmp lowmem/
DIR=$(echo normal/tmp/*)
DIR_LOWMEM=$(echo lowmem/tmp/*)
cp $DIR_LOWMEM/isolinux/boot.msg $DIR/isolinux/boot-lowmem.msg
cp $DIR_LOWMEM/isolinux/initrd.img $DIR/isolinux/lowmem.img
cp $DIR_LOWMEM/isolinux/isolinux.cfg $DIR/isolinux/isolinux-lowmem.cfg
rm -r lowmem/
mv normal/* ./
rm -r normal/
tar cvfj $NAME-$ARCH-upload.tar.bz2 tmp/
mv $NAME-$ARCH-upload.tar.bz2 ../
cd ..
rm -r iso-creator-$ARCH/
