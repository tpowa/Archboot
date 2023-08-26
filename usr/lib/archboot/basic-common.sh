#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
LANG=C
_ANSWER="/.$(basename "${0}")"
_RUNNING_ARCH="$(uname -m)"
_LOG="/dev/tty7"
_NO_LOG="/dev/null"
_LABEL="Exit"
_DLPROG="wget -q"
_MIRRORLIST="/etc/pacman.d/mirrorlist"
_KERNELPKG="linux"

# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_progress() {
cat <<EOF
XXX
${1}
${2}
XXX
EOF
}

_show_login() {
    [[ -e "/.${_ANSWER}-running" ]] && rm "/.${_ANSWER}-running"
    clear
    echo ""
    agetty --show-issue
    echo ""
    cat /etc/motd
}

_abort() {
    if _dialog --yesno "Abort$(echo "${_TITLE}" | cut -d '|' -f3) ?" 5 45; then
        [[ -e "${_ANSWER}-running" ]] && rm "${_ANSWER}-running"
        [[ -e "${_ANSWER}" ]] && rm "${_ANSWER}"
        clear
        exit 1
    else
        _CONTINUE=""
    fi
}

_check() {
    if [[ -e "${_ANSWER}-running" ]]; then
        clear
        echo "${0} already runs on a different console!"
        echo "Please remove ${_ANSWER}-running first to launch ${0}!"
        exit 1
        fi
    : >"${_ANSWER}"
    : >"${_ANSWER}-running"
}

_cleanup() {
    [[ -e "${_ANSWER}-running" ]] && rm "${_ANSWER}-running"
    clear
    exit 0
}

_run_update_environment() {
    if update | grep -q latest-install; then
        update -latest-install
    else
        update -latest
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
