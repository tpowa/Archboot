#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
LANG=C
_APPNAME=${0##*/}
_usage () {
    echo "Tests for Archboot Environment"
    echo "-------------------------------------------------"
    echo "Basic tests for Archboot"
    echo ""
    echo "usage: ${_APPNAME} run"
    exit 0
}
[[ -z "${1}" || "${1}" != "run" ]] && _usage
echo "Boot Test..."
if dmesg | grep -q error; then
    dmesg | grep error
    echo "Test failed!"
    _TEST_FAIL=1
fi
echo "Binary Test..."
for i in /usr/bin/*; do
    if ldd "${i}" 2>${_NO_LOG} | grep -q 'not found'; then
        echo "${i}"
        ldd "${i}" | grep 'not found'
        echo "Test failed!"
        _TEST_FAIL=1
    fi
done
echo "Base Binary Test..."
_BASE_BLACKLIST="arpd backup bashbug enosys exch fsck.cramfs fsck.minix gawk-5.3.0 gawkbug gencat getconf iconv iconvconfig lastlog2 ld.so locale lsclocks makedb makepkg-template memusage memusagestat mkfs.bfs mkfs.cramfs mkfs.minix mtrace newgidmap newuidmap pcprofiledump pldd pstree.x11 restore routel run0 setpgid sln sotruss sprof systemd-confext systemd-cryptsetup systemd-delta systemd-repart systemd-run systemd-vmspawn varlinkctl xtrace"
archboot-binary-check.sh base
for i in $(grep '/usr/bin/' binary.txt | sed -e 's#^/usr/bin/##g'); do
    if ! echo "${_BASE_BLACKLIST}" | grep -qw "${i}"; then
        echo "Test failed!"
        echo "${i}" >> base-binary.txt
        _TEST_FAIL=1
    fi
    cat base-binary.txt
done
echo "Pacman Package Database Test..."
if ! archboot-not-installed.sh; then
    echo "Test failed!"
    cat not-installed.txt
    _TEST_FAIL=1
fi
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
