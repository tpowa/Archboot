#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_MS_GUID="77fa9abd-0359-4d32-bd60-28f4e78f784b"
_MS_PATH="https://www.microsoft.com/pkiops/certs"
_MS_CERTS="MicWinProPCA2011_2011-10-19 MicCorUEFCA2011_2011-06-27 'windows uefi ca 2023' 'microsoft uefi ca 2023'"
_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Generate Secure Boot Keys, MOK Files\e[m"
    echo -e "\e[1m-----------------------------------------------\e[m"
    echo "This script generates all needed keys for a Secure Boot setup."
    echo -e "It will include the \e[1m2\e[m needed Microsoft certificates, in order"
    echo "to avoid soft bricking of devices."
    echo -e "Backup of your existing keys are put to \e[1mBACKUP\e[m directory."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} -name=<your name> <directory>\e[m"
    exit 0
}
[[ -z "${1}" || -z "${2}" ]] && _usage
_DIR="${2}"
while [ $# -gt 0 ]; do
    case ${1} in
        -name=*|--name=*) _NAME="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
        -h|--h|-help|--help|?) _usage ;;
        esac
    shift
done
if [[ -z "${_NAME}" ]]; then
    echo "ERROR: no name specified"
    _usage
    #shellcheck disable=2317
    exit 1
fi
_root_check
# archboot
[[ -e /usr/bin/mkkeys.sh ]] && _MKKEYS="mkkeys.sh"
# normal system
[[ -e /usr/bin/archboot-mkkeys.sh ]] && _MKKEYS="archboot-mkkeys.sh"
if [[ -n "${_DIR}" ]]; then
    [[ ! -d "${_DIR}" ]] && mkdir -p "${_DIR}"
    cd "${_DIR}" || exit 1
    echo "Backup old keys in $_DIR/BACKUP..."
    [[ ! -d "BACKUP" ]] && mkdir BACKUP
    efi-readvar -v PK -o BACKUP/old_PK.esl
    efi-readvar -v KEK -o BACKUP/old_KEK.esl
    efi-readvar -v db -o BACKUP/old_db.esl
    efi-readvar -v dbx -o BACKUP/old_dbx.esl
    cd BACKUP || exit 1; mokutil --export; cd .. || exit 1
    echo "Generating Keys in ${_DIR}"
    # add mkkeys.sh
    ${_MKKEYS} <<EOF
${_NAME}
EOF
    # download MS Certificates, else EFI might get broken!
    echo "Downloading Microsoft Certificates..."
    for i in ${_MS_CERTS}; do
        ${_DLPROG} -O "${_MS_PATH}/${i}.crt" || exit 1
    done
    echo "Creating EFI Signature Lists from Microsoft's DER format db certificates..."
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_db.esl MicWinProPCA2011_2011-10-19.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_UEFI_db.esl MicCorUEFCA2011_2011-06-27.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_db_2023.esl 'windows uefi ca 2023.crt'
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_UEFI_db_2023.esl 'microsoft uefi ca 2023.crt'
    cat MS_Win_db_2011.esl MS_Win_db_2023.esl MS_UEFI_db_2011.esl MS_UEFI_db_2023.esl > MS_db.esl
    echo "Creating an EFI Signature List from Microsoft's DER format KEK certificates..."
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_KEK_2011.esl MicCorKEKCA2011_2011-06-24.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_KEK_2023.esl 'microsoft corporation kek 2k ca 2023.crt'
    cat MS_Win_KEK_2011.esl MS_Win_KEK_2023.esl > MS_Win_KEK.esl
    echo "Signing a db variable update with your KEK..."
    sign-efi-sig-list -a -g ${_MS_GUID} -k KEK.key -c KEK.crt db MS_db.esl add_MS_db.auth
    echo "Signing a KEK variable update with your PK..."
    sign-efi-sig-list -a -g ${_MS_GUID} -k PK.key -c PK.crt KEK MS_Win_KEK.esl add_MS_Win_KEK.auth
    # generate new machine owner key
    echo "Generating Machine Owner Key (MOK) ..."
    openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.crt -nodes -days 3650 -subj "/CN=${_NAME}/"
    openssl x509 -in MOK.crt -out MOK.cer -outform DER
    DIRS="DB KEK MOK PK noPK"
    for i in $DIRS; do
        [[ ! -d "$i" ]] && mkdir "$i"
        mv "${i}".* "${i}"
    done
    mv DB db
    [[ ! -d "GUID" ]] && mkdir GUID
    [[ ! -d "MS" ]] && mkdir MS
    mv GUID.txt GUID
    mv ./*.crt ./*.auth ./*.esl MS
    cd ..
    chmod 700 "${_DIR}"
    echo "Finished: Keys created in ${_DIR}"
else
    echo "ERROR: no directory specified"
    _usage
    #shellcheck disable=2317
    exit 1
fi
