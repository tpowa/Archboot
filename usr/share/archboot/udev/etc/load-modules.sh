#! /bin/sh
# Implement blacklisting for udev-loaded modules
#   Includes module checking
# - Aaron Griffin, Tobias Powalowski and Thomas Bächler for Archlinux
[ $# -ne 1 ] && exit 1

MODPROBE="/sbin/modprobe"
RESOLVEALIAS="${MODPROBE} --resolve-alias"

if [ -f /proc/cmdline ]; then 
    for cmd in $(cat /proc/cmdline); do
        case $cmd in
            disablemodules=*) eval $cmd ;;
            load_modules=off) exit ;;
        esac
    done
    #parse cmdline entries of the form "disablemodules=x,y,z"
    if [ -n "$disablemodules" ]; then
        BLACKLIST="$BLACKLIST $(echo $disablemodules | sed 's|,| |g')"
    fi
fi

# get the real names from modaliases
i="$($RESOLVEALIAS $1)"
# add disablemodules= from commandline to blacklist
j="$(echo ${BLACKLIST} | sed  's|-|_|g')"
# add blacklisted modules from /tmp/.ide-blacklist
if [ -s /tmp/.ide-blacklist ]; then
	for l in $(sort -u /tmp/.ide-blacklist); do
		j="$j $l"
	done
fi

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
