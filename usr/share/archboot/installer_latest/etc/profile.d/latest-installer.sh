# don't run ttyS0 as first device
[[ -z $TTY ]] && TTY=$(tty)
TTY=${TTY#/dev/}
cd /
echo "Welcome to Arch Linux (archboot environment):"
echo "--------------------------------------------------------------------"
echo "Go and get a cup of coffee, on a fast internet connection (100Mbit),"
echo "you can start in 5 minutes with your tasks..."
echo ""
if [[ "${TTY}" == "tty1" ]]; then
    echo "10 seconds time to hit CTRL-C to stop the process now..."
    sleep 10
    echo "Starting assembling of latest archboot environment with package cache..."
    echo ""
    echo "Running now: update-installer.sh -latest-install"
    update-installer.sh -latest-install
elif [[ "${TTY}" == "ttyS0" ]]; then
    echo "Running update-installer.sh -latest-install on tty1, please wait ..."
    echo "Logging is done on tty7 ..."
fi
