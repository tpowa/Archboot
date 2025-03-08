#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Localization"

_locale_menu() {
    _LOCALE=""
    while [[ -z "${_LOCALE}" ]]; do
        _LOCALE=""
        _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER Other"
        _OTHER_LOCALES="be_BY Belarusian bg_BG Bulgarian cs_CZ Czech da_DK Dansk fi_FI Finnish el_GR Greek hu_HU Hungarian it_IT Italian lt_LT Lithuanian lv_LV Latvian mk_MK Macedonian nl_NL Dutch nn_NO Norwegian pl_PL Polish ro_RO Romanian ru_RU Russian sk_SK Slovak sr_RS Serbian sv_SE Swedish tr_TR Turkish uk_UA Ukrainian"
        _CANCEL=""
        #shellcheck disable=SC2086
        _dialog --cancel-label "${_LABEL}" --title " Locale " --menu "" 12 35 5 ${_LOCALES} 2>${_ANSWER} || _abort
        _LOCALE=$(cat "${_ANSWER}")
        if [[ "${_LOCALE}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            if _dialog  --title " Other Locale " --menu "" 17 35 11 ${_OTHER_LOCALES} 2>${_ANSWER}; then
                _LOCALE=$(cat ${_ANSWER})
            else
                _LOCALE=""
            fi
        fi
    done
}

_vconsole_keymap() {
    _LIST_MAPS="localectl list-keymaps --no-pager"
    _KEYMAPS="us de es fr pt be bg br ca cz dk et fi gr hu it lt lv mk nl no pl ro ru sk sr sv tr ua"
    _LOW_LOCALE="$(echo "${_LOCALE}" | tr "[:upper:]" "[:lower:]")"
    for i in ${_KEYMAPS}; do
        echo "${_LOW_LOCALE}" | rg -q "${i}" && _DETECTED_KEYMAP="${i}"
        [[ -n ${_DETECTED_KEYMAP} ]] && break
    done
    _KEYMAP=""
    # Germany and Estonian
    if ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "nodeadkeys"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "nodeadkeys")"
    # Europe
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}-latin1$"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}-latin1$")"
    # Bulgarian
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}_pho-utf8$"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}_pho-utf8$")"
    # Czech and Slovak
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}-qwertz"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}-qwertz$")"
    # Serbian
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}-latin"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}-latin$")"
    # Turkish
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}q$"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}q$")"
    # Ukrainian
    elif ${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg -q "^${_DETECTED_KEYMAP}-utf"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}" | rg "^${_DETECTED_KEYMAP}-utf$")"
    # fallback to plain  ${_KEYMAP}
    elif ${_LIST_MAPS} | rg -q "^${_DETECTED_KEYMAP}$"; then
        _KEYMAP="$(${_LIST_MAPS} | rg "^${_DETECTED_KEYMAP}$")"
    fi
}

_localize_task() {
    echo "LANG=${_LOCALE}.UTF-8" > /etc/locale.conf
    echo LC_COLLATE=C >> /etc/locale.conf
    localectl set-locale "${_LOCALE}.UTF-8" &>"${_NO_LOG}"
    #shellcheck disable=SC2016
    sd '(^[a-z])' '#$1' /etc/locale.gen
    sd "^#${_LOCALE}.UTF-8" "${_LOCALE}.UTF-8" /etc/locale.gen
    locale-gen &>"${_NO_LOG}"
    # Terminus font size detection
    if rg -q '^FONT=.*32' /etc/vconsole.conf; then
        _FONT="ter-v32n"
    else
        _FONT="ter-v16n"
    fi
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    # set running VC too
    export LANG="${_LOCALE}.UTF-8"
    : > /.localize
    { echo "### localize"
    echo "echo Localization..."
    echo "echo \"LANG=${_LOCALE}.UTF-8\" > /etc/locale.conf"
    echo "echo LC_COLLATE=C >> /etc/locale.conf"
    echo "localectl set-locale \"${_LOCALE}.UTF-8\" &>\"${_NO_LOG}\""
    #shellcheck disable=SC2016
    echo "sd '(^[a-z])' '#\$1' /etc/locale.gen"
    echo "sd \"^#${_LOCALE}.UTF-8\" \"${_LOCALE}.UTF-8\" /etc/locale.gen"
    echo "locale-gen &>\"${_NO_LOG}\""
    echo "echo KEYMAP=\"${_KEYMAP}\" > /etc/vconsole.conf"
    echo "echo FONT=\"${_FONT}\" >> /etc/vconsole.conf"
    echo "systemctl restart systemd-vconsole-setup"
    # set running VC too
    echo "export LANG=\"${_LOCALE}.UTF-8\""
    echo ": > /.localize"
    echo ""
    } >> "${_TEMPLATE}"
    rm /.archboot
}

_run() {
    : >/.archboot
    _localize_task &
    _progress_wait "0" "99" "Using ${_LOCALE}.UTF-8 and ${_KEYMAP}..." "0.25"
    _progress "100" "Localization completed successfully."
    sleep 2
}

_localize() {
    _run | _dialog --title " Localization " --no-mouse --gauge "Using ${_LOCALE}.UTF-8 and ${_KEYMAP}..." 6 50 0
}

_check
while [[ -z "${_LOCALE}" ]]; do
    _locale_menu
    _vconsole_keymap
done
_localize
_cleanup
