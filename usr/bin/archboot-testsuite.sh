#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
LANG=C
_LOG=testsuite.log
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
echo "Boot Test running..."
if dmesg | grep -q error; then
    dmesg | grep error >>dmesg-error.txt
    _TEST_FAIL=1
fi
if [[ -f dmesg-error.txt ]]; then
    echo "Test failed!"
    cat dmesg-error.txt
else
    echo "Test run succesfully."
fi
echo "Binary Test running..."
for i in /usr/bin/*; do
    if ldd "${i}" 2>${_NO_LOG} | grep -q 'not found'; then
        echo "${i}" >>binary-error.txt
        ldd "${i}" | grep 'not found'
        _TEST_FAIL=1
    fi
done
if [[ -f binary-error.txt ]]; then
    echo "Test failed!"
    cat binary-error.txt
else
    echo "Test run succesfully."
fi
[[ -f binary-error.txt ]] && cat binary-error.txt
echo "Base Binary Test running..."
_BASE_BLACKLIST="arpd backup bashbug enosys exch fsck.cramfs fsck.minix gawk-5.3.0 \
gawkbug gencat getconf iconv iconvconfig lastlog2 ld.so locale lsclocks makedb makepkg-template \
memusage memusagestat mkfs.bfs mkfs.cramfs mkfs.minix mtrace newgidmap newuidmap pcprofiledump \
pldd pstree.x11 restore routel run0 setpgid sln sotruss sprof systemd-confext systemd-cryptsetup \
systemd-delta systemd-repart systemd-run systemd-vmspawn varlinkctl xtrace"
archboot-binary-check.sh base &>>"${_LOG}"
for i in $(grep '/usr/bin/' binary.txt | sed -e 's#^/usr/bin/##g'); do
    if ! echo "${_BASE_BLACKLIST}" | grep -qw "${i}"; then
        echo "${i}" >> base-binary-error.txt
        _TEST_FAIL=1
    fi
done
if [[ -f base-binary-error.txt ]]; then
    echo "Test failed!"
    cat base-binary-error.txt
else
    echo "Test run succesfully."
fi
# uninstall base again!
pacman --noconfirm -Rdd base
echo "Pacman Package Database Test running..."
archboot-not-installed.sh &>>"${_LOG}"
if [[ -s not-installed.txt ]]; then
    echo "Test failed!"
    cat not-installed.txt
    _TEST_FAIL=1
fi
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
