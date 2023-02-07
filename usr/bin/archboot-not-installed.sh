#!/bin/bash
if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi
rm -r /usr/share/licenses
pacman -Sy
pacman -Q | cut -d ' ' -f1 >packages.txt
for i in $(cat packages.txt); do
	rm -r /var/lib/pacman/local/$i*
	if pacman -S $i --noconfirm &>>log.txt; then
		echo $i >> uninstalled.txt
	else
	   pacman -S $i --noconfirm --overwrite '*'
	fi
done
