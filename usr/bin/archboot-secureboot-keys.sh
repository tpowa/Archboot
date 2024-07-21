#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
usage () {
    echo -e "\e[1mGenerate Secure Boot keys,MOK files and backup existing keys:\e[m"
    echo -e "\e[1m-------------------------------------------------------------\e[m"
    echo "This script generates all needed keys for a Secure Boot setup."
    echo -e "It will include the \e[1m2\e[m needed Microsoft certificates, in order"
    echo "to avoid soft bricking of devices."
    echo -e "Backup of your existing keys are put to \e[1mBACKUP\e[m directory."
    echo ""
    echo -e "\e[1musage: ${_BASENAME} -name=<your name> <directory>\e[m"
    exit 0
}
[[ -z "${1}" || -z "${2}" ]] && usage
_DIR="${2}"
while [ $# -gt 0 ]; do
	case ${1} in
		-name=*|--name=*) NAME="$(echo "${1}" | rg -o '=(.*)' -r '$1')" ;;
		-h|--h|?) usage ;; 
        esac
	shift
done
if [[ -z "${NAME}" ]]; then
    echo "ERROR: no name specified"
    usage
    #shellcheck disable=2317
    exit 1
fi
_root_check
# archboot
[[ -e /usr/bin/mkkeys.sh ]] && MKKEYS="mkkeys.sh"
# normal system
[[ -e /usr/bin/archboot-mkkeys.sh ]] && MKKEYS="archboot-mkkeys.sh"
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
    echo "Generating Keys in $_DIR"
    # add mkkeys.sh
    ${MKKEYS} <<EOF
${NAME} 
EOF
    # download MS Certificates, else EFI might get broken!
    ${_DLPROG} -O https://www.microsoft.com/pkiops/certs/MicWinProPCA2011_2011-10-19.crt
    ${_DLPROG} -O https://www.microsoft.com/pkiops/certs/MicCorUEFCA2011_2011-06-27.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_Win_db.esl MicWinProPCA2011_2011-10-19.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_UEFI_db.esl MicCorUEFCA2011_2011-06-27.crt
    cat MS_Win_db.esl MS_UEFI_db.esl > MS_db.esl
    sign-efi-sig-list -a -g 77fa9abd-0359-4d32-bd60-28f4e78f784b -k KEK.key -c KEK.crt db MS_db.esl add_MS_db.auth
    openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.crt -nodes -days 3650 -subj "/CN=${NAME}/"
    openssl x509 -in MOK.crt -out MOK.cer -outform DER
    DIRS="DB KEK MOK PK noPK"
    for i in $DIRS; do
        [[ ! -d "$i" ]] && mkdir "$i"
        mv "${i}".* "${i}"
    done
    mv DB db
    [[ ! -d "GUID" ]] && mkdir GUID
    [[ ! -d "MS" ]] && mkdir MS
    mv myGUID.txt GUID
    mv ./*.crt ./*.auth ./*.esl MS
    cd ..
    chmod 700 "${_DIR}"
    echo "Finished: Keys created in ${_DIR}"
else
    echo "ERROR: no directory specified"
    usage
    #shellcheck disable=2317
    exit 1
fi
