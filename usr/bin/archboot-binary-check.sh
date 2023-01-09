#!/usr/bin/env bash
#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_APPNAME="$(basename "${0}")"
_usage () {
    echo "${_BASENAME}: usage"
    echo "Check on missing binaries in archboot environment"
    echo "-------------------------------------------------"
    echo "Usage: ${_APPNAME} <package>"
    echo "This will check binaries from package, if they exist"
    echo "and report missing to binary.txt"
    exit 0
}
[[ -z "${1}" ]] && _usage
if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi
# update pacman db first
pacman -Sy
if [[ "${1}" == "base" ]]; then
    _PACKAGE="$(pacman -Qi base | grep Depends | cut -d ":" -f2)"
else
    _PACKAGE="${1}"
fi
echo "${_PACKAGE}" >binary.txt
#shellcheck disable=SC2086
for i in $(pacman -Ql ${_PACKAGE} | grep "/usr/bin/..*"$ | cut -d' ' -f2); do
	command -v "${i}" >/dev/null 2>&1 || echo "${i}" >>binary.txt
done
