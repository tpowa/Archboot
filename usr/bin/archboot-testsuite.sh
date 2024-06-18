#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_LANG=C
_LOG=testsuite.log
_APPNAME=${0##*/}
_usage () {
    echo -e "\e[1mTestsuite for Archboot Environment\e[m"
    echo -e "\e[1m---------------------------------------------\e[m"
    echo "Run automatic tests to detect errors/changes."
    echo ""
    echo -e "usage: \e[1m${_APPNAME} run\e[m"
    exit 0
}
_run_test () {
    echo -e "\e[1mTestsuite checking ${1}...\e[m"
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
_run_test "journal"
if ! journalctl -p3 -xb | grep -q 'No entries'; then
    journalctl -p3 -xb >>journal-error.txt
    _TEST_FAIL=1
fi
_result journal-error.txt
_run_test "ldd on /usr/bin"
for i in /usr/bin/*; do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -q 'not found'; then
        echo "${i}" >>bin-binary-error.txt
        ldd "${i}" | grep 'not found' >>bin-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result bin-binary-error.txt
_run_test "ldd on executables in /usr/lib"
for i in $(fd -u -t x -E '*.so.*' -E '*.so' . /usr/lib); do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -q 'not found'; then
        echo "${i}" >>lib-binary-error.txt
        ldd "${i}" | grep 'not found' >>lib-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result lib-binary-error.txt
_run_test "ldd on /usr/lib"
# ignore wrong reported libsystemd-shared by libsystemd-core
for i in $(fd -u '.so' /usr/lib); do
    if ldd "${i}" 2>"${_NO_LOG}" | grep -v -E 'tree_sitter|libsystemd-shared' | grep -q 'not found'; then
        echo "${i}" >>lib-error.txt
        ldd "${i}" | grep 'not found' >>lib-error.txt
        _TEST_FAIL=1
    fi
done
_result lib-error.txt
_run_test "on missing base binaries"
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
_run_test "modules included /usr/lib/firmware"
if ! archboot-fw-check.sh run; then
    TEST_FAIL=1
fi
_result fw-error.txt
# uninstall base again!
pacman --noconfirm -Rdd base gettext &>>"${_LOG}"
_run_test "licenses"
for i in $(pacman -Ql $(pacman -Q | cut -d ' ' -f 1) | cut -d ' ' -f2 | grep 'share/licenses'); do
    [[ -e "${i}" ]] || echo "${i}" | grep -v '/xz/' >>license-error.txt
done
_result license-error.txt
echo -e "Starting none tracked files in \e[1m10\e[m seconds... \e[1;92mCTRL-C\e[m to stop now."
read -r -t 10
_run_test "none tracked files in /usr/lib... this takes a while"
for i in $(fd -u -E '/modules/' -E '/udev/' -E 'gconv-modules.cache' . /usr/lib); do
    pacman -Qo ${i} &>${_NO_LOG} || echo ${i} >> pacman-error.log
done
_result pacman-error.log
echo -e "Starting pacman database check in \e[1m10\e[m seconds... \e[1;92mCTRL-C\e[m to stop now."
read -r -t 10
_run_test "pacman database... this takes a while"
archboot-not-installed.sh &>>"${_LOG}"
_result not-installed.txt
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
