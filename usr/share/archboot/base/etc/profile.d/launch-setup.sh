cd /
echo "Hit ENTER to enter the zsh shell ..."
read
clear
if ! [ -e /tmp/.setup ]; then
	[ -e /usr/bin/setup ] && setup
fi
