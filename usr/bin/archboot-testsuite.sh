#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
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
if ! journalctl -p3 -xb | rg -q 'No entries'; then
    journalctl -p3 -xb >>journal-error.txt
    _TEST_FAIL=1
fi
_result journal-error.txt
_run_test "ldd on /usr/bin"
for i in /usr/bin/*; do
    if ldd "${i}" 2>"${_NO_LOG}" | rg -q 'not found'; then
        echo "${i}" >>bin-binary-error.txt
        ldd "${i}" | rg 'not found' >>bin-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result bin-binary-error.txt
_run_test "ldd on executables in /usr/lib"
for i in $(fd -u -t x -E '*.so.*' -E '*.so' -E 'ssh-sk-helper' . /usr/lib); do
    if ldd "${i}" 2>"${_NO_LOG}" | rg -q 'not found'; then
        echo "${i}" >>lib-binary-error.txt
        ldd "${i}" | rg 'not found' >>lib-binary-error.txt
        _TEST_FAIL=1
    fi
done
_result lib-binary-error.txt
_run_test "ldd on /usr/lib"
# ignore wrong reported libsystemd-shared by libsystemd-core
for i in $(fd -u '.so' /usr/lib); do
    if ldd "${i}" 2>"${_NO_LOG}" | rg -v 'tree_sitter|libsystemd-shared' | rg -q 'not found'; then
        echo "${i}" >>lib-error.txt
        ldd "${i}" | rg 'not found' >>lib-error.txt
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
for i in $(rg '/usr/bin/(.*)' -r '$1' binary.txt); do
    if ! echo "${_BASE_BLACKLIST}" | rg -qw "${i}"; then
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
for i in $(pacman -Ql $(pacman -Q | sd ' .*' '') | rg -o '/usr/share/licenses/.*'); do
    [[ -e "${i}" ]] || echo "${i}" | rg -v '/xz/' >>license-error.txt
done
_result license-error.txt
_run_test "filesystems"
for i in bcachefs btrfs ext4 swap vfat xfs; do
    dd if=/dev/zero of=/test.img bs=1M count=1000 &>"${_NO_LOG}"
    sync
    if [[ "${i}" == "swap" ]]; then
        mkswap /test.img &>"${_NO_LOG}" || echo "Creation error: ${i}" >> filesystems-error.log
        sync
    else
        mkfs.${i} /test.img &>"${_NO_LOG}" || echo "Creation error: ${i}" >> filesystems-error.log
        sync
        mount -o loop /test.img /mnt &>"${_NO_LOG}" || echo "Mount error: ${i}" >> filesystems-error.log
        umount /mnt
    fi
done
_result filesytems-error.log
_run_test "blockdevices"
dd if=/dev/zero of=/test.img bs=1M count=1000 &>"${_NO_LOG}"
sync
losetup --show -f /test.img
mdadm --create /dev/md0 --run --level=0 --raid-devices=1 /dev/loop0 &>"${_NO_LOG}" || echo "Creation error: mdadm" >> blockdevices-error.log
wipefs -a -f /dev/md0  &>"${_NO_LOG}"
mdadm --manage --stop /dev/md0 &>"${_NO_LOG}" || echo "Stop error: mdadm" >> blockdevices-error.log
wipefs -a -f /dev/loop0 &>"${_NO_LOG}"
dd if=/dev/zero of=/test.img bs=1M count=10 &>"${_NO_LOG}"
sync
_result blockdevices-error.log
_run_test "Wi-Fi iwctl"
archboot-hwsim.sh test &>"${_NO_LOG}"
iwctl station wlan1 scan
sleep 5
iwctl station wlan1 get-networks | rg -q test || echo "Wi-Fi iwctl get-networks error" >> iwctl-error.log
iwctl --passphrase=12345678 station wlan1 connect test || echo "Wi-Fi iwctl connect error" >> iwctl-error.log
iwctl station wlan1 disconnect || echo "Wi-Fi iwctl disconnect error" >> iwctl-error.log
_result iwctl-error.log
echo -e "Starting none tracked files in \e[1m10\e[m seconds... \e[1;92mCTRL-C\e[m to stop now."
sleep 10
_run_test "none tracked files in /usr/lib... this takes a while"
for i in $(fd -u -E '/modules/' -E '/udev/' -E 'gconv-modules.cache' -E '/locale-archive' . /usr/lib); do
    #shellcheck disable=SC2086
    pacman -Qo ${i} &>${_NO_LOG} || echo ${i} >> pacman-error.log
done
_result pacman-error.log
echo -e "Starting pacman database check in \e[1m10\e[m seconds... \e[1;92mCTRL-C\e[m to stop now."
sleep 10
_run_test "pacman database... this takes a while"
archboot-not-installed.sh &>>"${_LOG}"
_result not-installed.txt
[[ -n "${_TEST_FAIL}" ]] && exit 1
# vim: set ft=sh ts=4 sw=4 et:
