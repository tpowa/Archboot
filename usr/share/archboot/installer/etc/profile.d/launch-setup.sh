# don't run ttyS0 as first device
if [[ -e /usr/bin/setup ]]; then
    cd /
    echo "Hit ENTER to enter the zsh shell ..."
    read
    clear
    if ! [ -e /tmp/.setup ]; then
        setup
    fi
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 3200000 ]] ; then
    echo -e "\033[1mWelcome to \033[36mArch Linux \033[34m(archboot environment)\033[0m"
    echo -e "\033[1m--------------------------------------------------------------------\033[0m"
    echo -e "\033[91mNot engough RAM detected! Please add more than 3.2GB RAM. Aborting ...\033[0;25m"
    echo "Hit ENTER to enter the shell ..."
    read
else
    [[ -z $TTY ]] && TTY=$(tty)
    TTY=${TTY#/dev/}
    cd /
    echo -e "\033[1mWelcome to \033[36mArch Linux \033[34m(archboot environment)\033[0m"
    echo -e "\033[1m--------------------------------------------------------------------\033[0m"
    echo -e "\033[93mGo and get a cup of coffee. Depending on your system setup,\033[0m"
    echo -e "\033[93myou can start with your tasks in about 5 minutes ...\033[0m"
    echo ""
    if [[ "${TTY}" == "tty1" ]]; then
        echo -e "\033[91m10 seconds\033[0;25m time to hit \033[92mCTRL-C\033[0m to \033[91mstop\033[0m the process \033[1mnow ...\033[0m"
        sleep 10
        echo -e "\033[1mStarting\033[0m assembling of archboot environment with package cache ..."
        echo ""
        echo -e "\033[1mRunning now:\033[0m \033[92mupdate-installer.sh -latest-install\033[0m"
        update-installer.sh -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 2>/dev/null
    elif [[ "${TTY}" == "ttyS0" || "${TTY}" == "ttyAMA0" || "${TTY}" == "ttyUSB0" ]]; then
        echo -e "\033[1mRunning\033[0m \033[92mupdate-installer.sh -latest-install\033[0m on \033[1mtty1\033[0m, please wait ...\033[0m"
        echo -e "\033[1mProgress is shown here ...\033[0m"
    fi
fi
