cd /
echo "Welcome to Arch Linux (archboot environment):"
echo "--------------------------------------------------------------------"
echo "Go and get a cup of coffee, on a fast internet connection (100Mbit),"
echo "you can start in 5 minutes with your tasks..."
echo ""
echo "10 seconds time to hit CTRL-C to stop the process now..."
sleep 10
echo ""
echo "Starting assembling of latest archboot environment with package cache..."
echo ""
echo "Running now: update-installer.sh -latest-install"
update-installer.sh -latest-install
