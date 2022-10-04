#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_install_kde_wayland() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma Wayland now ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_STANDARD_PACKAGES} ${_STANDARD_BROWSER} ${_PLASMA_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\033[1mStep 4/5:\033[0m Configuring KDE/Plasma Wayland ..."
        _configure_plasma >/dev/tty7 2>&1
	else
		echo -e "\033[1mStep 3/5:\033[0m Installing KDE/Plasma Wayland already done ..."
		echo -e "\033[1mStep 4/5:\033[0m Configuring KDE/Plasma Wayland already done ..."
    fi
}

_start_kde_wayland() {
    echo -e "Launching KDE/Plasma Wayland now, logging is done on \033[1m/dev/tty7\033[0m ..."
	echo -e "To relaunch KDE/Plasma Wayland use: \033[92mplasma-wayland\033[0m"
    echo "exec dbus-run-session startplasma-wayland >/dev/tty7 2>&1" > /usr/bin/plasma-wayland
    chmod 755 /usr/bin/plasma-wayland
    plasma-wayland
}
