#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_kde() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_XORG_PACKAGE} ${_VNC_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop ..."
        _configure_plasma >/dev/tty7 2>&1
	else
		echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma desktop already done ..."
		echo -e "\033[1mStep 4/5:\033[0m Configuring KDE desktop already done ..."
    fi
}

_start_kde() {
    echo -e "Launching KDE/Plasma now, logging is done on \033[1m/dev/tty8\033[0m ..."
    echo "export DESKTOP_SESSION=plasma" > /root/.xinitrc
    echo "exec startplasma-x11" >> /root/.xinitrc
    startx >/dev/tty8 2>&1
    echo -e "To relaunch KDE desktop use: \033[92mstartx\033[0m"
}
