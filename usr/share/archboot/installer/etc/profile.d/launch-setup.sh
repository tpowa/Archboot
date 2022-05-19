# don't run ttyS0 as first device
_welcome () {
    echo -e "\033[1mWelcome to \033[36mArch Linux \033[34m(archboot environment)\033[0m"
    echo -e "\033[1m--------------------------------------------------------------------\033[0m"
}

_enter_shell() {
    cd /
    echo -e "Hit \033[1m\033[92mENTER\033[0m for \033[1mshell\033[0m login."
    read
    clear
}

if [[ -e /usr/bin/setup ]]; then
    _enter_shell
    if ! [[ -e /tmp/.setup ]]; then
        setup
    fi
elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 3200000 ]]; then
    _welcome
    echo -e "\033[1m\033[91mMemory check failed:\033[0m"
    echo -e "\033[1m\033[91m- Not engough memory detected! \033[0m"
    echo -e "\033[1m\033[93m- Please add more than 3.2GB RAM.\033[0m"
    echo -e "\033[1m\033[91mAborting ...\033[0m"
    _enter_shell
elif [[ $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -lt 4400000 &&\
        $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -gt 4015000 ]]; then
    _welcome
    echo -e "\033[1m\033[91mMemory check failed:\033[0m"
    echo -e "\033[1m\033[91m- Memory gap detected (4.0G - 4.4G RAM)\033[0m"
    echo -e "\033[1m\033[93m- Possibility of not working kexec boot.\033[0m"
    echo -e "\033[1m\033[93m- Please use more or less RAM.\033[0m"
    echo -e "\033[1m\033[91mAborting ...\033[0m"
    _enter_shell
else
    [[ -z $TTY ]] && TTY=$(tty)
    TTY=${TTY#/dev/}
    cd /
    _welcome
    echo -e "\033[1m\033[92mMemory checks finished successfully:\033[0m"
    echo -e "\033[1m\033[93mGo and get a cup of coffee. Depending on your system setup,\033[0m"
    echo -e "\033[1m\033[93myou can start with your tasks in about 5 minutes ...\033[0m"
    echo ""
    if [[ "${TTY}" == "tty1" ]]; then
        echo -e "\033[1m\033[91m10 seconds\033[0;25m time to hit \033[1m\033[92mCTRL-C\033[0m to \033[1m\033[91mstop\033[0m the process \033[1m\033[1mnow ...\033[0m"
        sleep 10
        echo -e "\033[1mStarting\033[0m assembling of archboot environment with package cache ..."
        echo ""
        echo -e "\033[1mRunning now: \033[92mupdate-installer.sh -latest-install\033[0m"
        update-installer.sh -latest-install | tee -a /dev/ttyS0 /dev/ttyAMA0 /dev/ttyUSB0 2>/dev/null
    elif [[ "${TTY}" == "ttyS0" || "${TTY}" == "ttyAMA0" || "${TTY}" == "ttyUSB0" ]]; then
        echo -e "Running \033[1m\033[92mupdate-installer.sh -latest-install\033[0m on \033[1mtty1\033[0m, please wait ...\033[0m"
        echo -e "\033[1mProgress is shown here ...\033[0m"
    fi
fi
