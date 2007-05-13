#! /bin/sh
# Implement blacklisting for udev-loaded modules
#   Includes module checking
# - Aaron Griffin & Tobias Powalowski for Archlinux
[ $# -ne 1 ] && exit 1

if [ -f /proc/cmdline ]; then 
	for cmd in $(cat /proc/cmdline); do
    		case $cmd in
        		*=*) eval $cmd ;;
    		esac
	done
fi

# get the real names from modaliases
i="$(/bin/moddeps $1)"
# add disablemodules= from commandline to blacklist
k="$(/bin/replace "${disablemodules}" ',')"
j="$(/bin/replace "${k}" '-' '_')"
# add blacklisted modules from /tmp/.ide-blacklist
if [ -s /tmp/.ide-blacklist ]; then
	for l in $(sort -u /tmp/.ide-blacklist); do
		j="$j $l"
	done
fi
# blacklist framebuffer modules
for x in $(echo /lib/modules/$(uname -r)/kernel/drivers/video/*/*fb*); do
	j="$j $(/usr/bin/basename $x .ko)"
done
for x in $(echo /lib/modules/$(uname -r)/kernel/drivers/video/*fb*); do
	j="$j $(/usr/bin/basename $x .ko)"
done

if [ "${j}" != "" ] ; then
	for n in ${i}; do
        	for o in ${j}; do
			if [ "$n" = "$o" ]; then
                		exit 1
            		fi
		done
	done
fi
/sbin/modprobe $1 > /dev/null 2>&1

# vim: set et ts=4:
