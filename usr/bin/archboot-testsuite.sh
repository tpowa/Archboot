#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_LOG=testsuite.log
_APPNAME=${0##*/}
_usage () {
    echo "Testsuite for Archboot Environment"
    echo "----------------------------------"
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
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_archboot_check
echo "Waiting for pacman keyring..."
_pacman_keyring
_run_test "Dmesg Error Check"
if dmesg | grep -q -w -E 'error'; then
    dmesg | grep -w -E 'error' >>dmesg-error.txt
    _TEST_FAIL=1
fi
_result dmesg-error.txt
_run_test "Binary Linking Test /usr/bin"
for i in /usr/bin/*; do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -q 'not found'; then
        echo "${i}" >>bin-binary-error.txt
        ldd "${i}" | grep 'not found' >>bin-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result bin-binary-error.txt
_run_test "Binary Linking Test /usr/lib/systemd"
for i in /usr/lib/systemd*; do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -q 'not found'; then
        echo "${i}" >>systemd-binary-error.txt
        ldd "${i}" | grep 'not found' >>systemd-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result systemd-binary-error.txt
_run_test "Library Linking Test /usr/lib"
# ignore wrong reported libsystemd-shared by libsystemd-core
for i in $(find /usr/lib | grep '.so$'); do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -v -E 'tree_sitter|libsystemd-shared' | grep -q 'not found'; then
        echo "${i}" >>lib-error.txt
        ldd "${i}" | grep 'not found' >>lib-error.txt
        _TEST_FAIL=1
    fi
done
_result lib-error.txt
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
_run_test "Firmware Check"
if ! archboot-fw-check.sh; then
    TEST_FAIL=1
fi
_result fw-error.txt
# uninstall base again!
pacman --noconfirm -Rdd base &>>"${_LOG}"
_run_test "Pacman Package Database Test"
archboot-not-installed.sh &>>"${_LOG}"
_result not-installed.txt
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
