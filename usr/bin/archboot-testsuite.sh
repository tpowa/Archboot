#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
LANG=C
_LOG=testsuite.log
_APPNAME=${0##*/}
_usage () {
    echo "Tests for Archboot Environment"
    echo "------------------------------"
    echo "usage: ${_APPNAME} run"
    exit 0
}
_run_test () {
    echo -e "\e[1m${1} running...\e[m"
}
_result() {
    if [[ -s ${1} ]]; then
        echo -e "\e[1;94m=> \e[1;91mFAILED\e[m"
        cat "${1}"
    else
        echo -e "\e[1;94m=> \e[1;92mOK\e[m"
    fi
}

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
}

[[ -z "${1}" || "${1}" != "run" ]] && _usage
echo "Waiting for pacman keyring..."
_gpg_check
_run_test "Boot Test"
if dmesg | grep -q error; then
    dmesg | grep error >>dmesg-error.txt
    _TEST_FAIL=1
fi
_result dmesg-error.txt
_run_test "Binary Test"
for i in /usr/bin/*; do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -q 'not found'; then
        echo "${i}" >>binary-error.txt
        echo ldd "${i}" | grep 'not found' >>binary-error.txt
        _TEST_FAIL=1
    fi
done
_result binary-error.txt
_run_test "Base Binary Test"
# not needed binaries, that are tolerated
_BASE_BLACKLIST="arpd backup bashbug enosys exch fsck.cramfs fsck.minix gawk-5.3.0 \
gawkbug gencat getconf iconv iconvconfig importctl lastlog2 ld.so locale lsclocks makedb \
makepkg-template memusage memusagestat mkfs.bfs mkfs.cramfs mkfs.minix mtrace newgidmap \
newuidmap pcprofiledump pldd pstree.x11 restore routel run0 setpgid sln sotruss sprof \
systemd-confext systemd-cryptsetup systemd-delta systemd-home-fallback-shell systemd-repart \
systemd-run systemd-vmspawn systemd-vpick varlinkctl xtrace"
archboot-binary-check.sh base &>>"${_LOG}"
#shellcheck disable=SC2013
for i in $(grep '/usr/bin/' binary.txt | sed -e 's#^/usr/bin/##g'); do
    if ! echo "${_BASE_BLACKLIST}" | grep -qw "${i}"; then
        echo "${i}" >> base-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result base-binary-error.txt
# uninstall base again!
pacman --noconfirm -Rdd base &>>"${_LOG}"
_run_test "Pacman Package Database Test"
archboot-not-installed.sh &>>"${_LOG}"
_result not-installed.txt
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
