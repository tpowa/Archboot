#! /bin/bash
TEMPFILE=$(mktemp /tmp/archboot-change-XXX)
for i in /usr/share/archboot/{base,capi4k,cpufreq,grub,iptables,isdn,kexec,lilo,net,openvpn,pacman,pam,ppp,pppoe,pptpclient,remote,shadow,udev,vpnc,wireless}; do
	cd $i
	for k in $(find ! -type d); do 
		diff -u $k /$k >>$TEMPFILE || (echo Changes found $i: $k)
	done
done
