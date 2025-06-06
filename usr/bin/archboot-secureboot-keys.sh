#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_MS_GUID="77fa9abd-0359-4d32-bd60-28f4e78f784b"
_MS_PATH="https://www.microsoft.com/pkiops/certs"
_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Generate Secure Boot Keys, MOK Files\e[m"
    echo -e "\e[1m-----------------------------------------------\e[m"
    echo "This script generates all needed keys for a Secure Boot setup."
    echo -e "It will include the \e[1m6\e[m needed Microsoft certificates, in order"
    echo "to avoid soft bricking of devices."
    echo -e "Backup of your existing keys are put to \e[1mBACKUP\e[m directory."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} -name=<your name> <directory>\e[m"
}
[[ -z "${1}" || -z "${2}" ]] && _usage
_DIR="${2}"
while [ $# -gt 0 ]; do
    case ${1} in
        -name=*|--name=*) _NAME="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
        -h|--h|-help|--help|?) _usage ;;
        esac
    shift
done
if [[ -z "${_NAME}" ]]; then
    echo "ERROR: no name specified"
    _usage
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
    # create custom keys
    _NAME=${_NAME} ${_MKKEYS}
    # download MS Certificates, else EFI might get broken!
    echo "Downloading Microsoft Certificates..."
    ${_DLPROG} -O ${_MS_PATH}/MicWinProPCA2011_2011-10-19.crt || exit 1
    ${_DLPROG} -O ${_MS_PATH}/MicCorUEFCA2011_2011-06-27.crt || exit 1
    ${_DLPROG} ${_MS_PATH}/windows%20uefi%20ca%202023.crt -o windows_uefi_ca_2023.crt || exit 1
    ${_DLPROG} ${_MS_PATH}/microsoft%20uefi%20ca%202023.crt -o microsoft_uefi_ca_2023.crt || exit 1
    ${_DLPROG} -O ${_MS_PATH}/MicCorKEKCA2011_2011-06-24.crt || exit 1
    ${_DLPROG} ${_MS_PATH}/microsoft%20corporation%20kek%202k%20ca%202023.crt -o microsoft_corporation_kek_2k_ca_2023.crt || exit 1
    echo "Creating EFI Signature Lists from Microsoft's DER format db certificates..."
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_db_2011.esl MicWinProPCA2011_2011-10-19.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_UEFI_db_2011.esl MicCorUEFCA2011_2011-06-27.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_db_2023.esl windows_uefi_ca_2023.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_UEFI_db_2023.esl microsoft_uefi_ca_2023.crt
    cat MS_Win_db_2011.esl MS_Win_db_2023.esl MS_UEFI_db_2011.esl MS_UEFI_db_2023.esl > MS_db.esl
    echo "Creating EFI Signature List from Microsoft's DER format KEK certificates..."
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_KEK_2011.esl MicCorKEKCA2011_2011-06-24.crt
    sbsiglist --owner ${_MS_GUID} --type x509 --output MS_Win_KEK_2023.esl 'microsoft_corporation_kek_2k_ca_2023.crt'
    cat MS_Win_KEK_2011.esl MS_Win_KEK_2023.esl > MS_Win_KEK.esl
    echo "Signing a db variable update with your KEK..."
    sign-efi-sig-list -a -g ${_MS_GUID} -k KEK.key -c KEK.crt db MS_db.esl add_MS_db.auth &>"${_NO_LOG}"
    echo "Signing a KEK variable update with your PK..."
    sign-efi-sig-list -a -g ${_MS_GUID} -k PK.key -c PK.crt KEK MS_Win_KEK.esl add_MS_Win_KEK.auth &>"${_NO_LOG}"
    # generate new machine owner key
    echo "Generating Machine Owner Key MOK..."
    openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.crt -nodes -days 3650 -subj "/CN=${_NAME}/" &>"${_NO_LOG}"
    openssl x509 -in MOK.crt -out MOK.cer -outform DER &>"${_NO_LOG}"
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
    echo "Keys created successfully in ${_DIR}"
else
    echo "ERROR: no directory specified"
    _usage
    exit 1
fi
