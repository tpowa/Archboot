cd /
echo "Welcome to Arch Linux (archboot environment):"
echo "----------------------------------------------------------------"
echo "Go get a cup of coffee, on a fast internet connection (100Mbit),"
echo "you can start in 5 minutes with your tasks..."
echo ""
echo "Have fun."
echo "Tobias Powalowski <tpowa@archlinux.org>"
echo ""
echo "5 seconds time to hit CTRL-C to stop the process now..."
sleep 5
echo "Starting assembling of latest archboot environment with package cache..."
echo ""
echo "Waiting 10 seconds for getting an internet connection through dhcpcd..."
echo ""
sleep 10
update-installer.sh -latest-install
