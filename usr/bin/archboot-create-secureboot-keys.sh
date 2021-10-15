#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

usage () {
	echo "Generate Secure Boot Keys and MOK files:"
	echo "--------------------------------------------------------------"
	echo "This script generates all needed keys for a Secure Boot setup."
	echo "It will include the 2 needed Microsoft certificates, in order"
	echo "to avoid soft bricking of devices."
	echo ""
        echo "Usage: -g <directory>"
        echo ""
	echo "PARAMETERS:"
	echo " -g             generate keys and MOK key in <directory>"
	echo " -h             This message."
	exit 0
}

[[ -z "${1}" || -z "${2}" ]] && usage

_DIR="$2"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) KEYS="1" ;;
		-h|--h|?) usage ;; 
        esac
	shift
done

if [[ "${KEYS}" == "1" ]]; then
    echo "Generating Keys in $_DIR"
    [[ ! -d $_DIR ]] && mkdir $_DIR
    cd $_DIR
    # add mkkeys.sh
    if [[ ! -f /usr/bin/mkkeys.sh ]]; then
        curl -s -L -O https://www.rodsbooks.com/efi-bootloaders/mkkeys.sh
        chmod 755 mkkeys.sh
        ./mkkeys.sh
    else
        mkkeys.sh
    fi
    # download MS Certificates, else EFI might get broken!
    curl -s -L -O https://www.microsoft.com/pkiops/certs/MicWinProPCA2011_2011-10-19.crt
    curl -s -L -O https://www.microsoft.com/pkiops/certs/MicCorUEFCA2011_2011-06-27.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_Win_db.esl MicWinProPCA2011_2011-10-19.crt
    sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output MS_UEFI_db.esl MicCorUEFCA2011_2011-06-27.crt
    cat MS_Win_db.esl MS_UEFI_db.esl > MS_db.esl
    sign-efi-sig-list -a -g 77fa9abd-0359-4d32-bd60-28f4e78f784b -k KEK.key -c KEK.crt db MS_db.esl add_MS_db.auth
    echo "Enter a Common Name to embed in the your MOK key:"
    read name
    openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.crt -nodes -days 3650 -subj "/CN=$name/"
    openssl x509 -in MOK.crt -out MOK.cer -outform DER
    DIRS="DB KEK MOK PK noPK"
    for i in $DIRS; do
        mkdir $i
        mv $i.* $i
    done
    mkdir {GUID,MS}
    mv myGUID.txt GUID
    mv *.crt *.auth *.esl MS
    cd ..
    echo "Finished: Keys created in $_DIR"
fi
