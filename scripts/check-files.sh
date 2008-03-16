#! /bin/bash
cd ..
for i in base capi4k cpufreq grub iptables isdn kexec lilo naim net openvpn pacman pam ppp pppoe pptpclient remote shadow udev vpnc wireless; do
	cd $i
	for k in $(find ! -type d); do 
		diff -u $k /$k >/dev/null || (echo Changes found $i: $k)
	done
	cd ..
done
