cd /
sed -i -e 's#zsh#sh#g' /etc/passwd
echo "Waiting 10 seconds for getting an internet connection through dhcpcd..."
sleep 10
update-installer.sh -latest-install
