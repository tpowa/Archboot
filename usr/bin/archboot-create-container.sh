#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_PWD="$(pwd)"
_BASENAME="$(basename "${0}")"
_CACHEDIR=""$1"/var/cache/pacman/pkg"
_CLEANUP_CACHE=""
_SAVE_RAM=""
_LINUX_FIRMWARE=""
_DIR=""

usage () {
	echo "CREATE ARCHBOOT CONTAINER"
	echo "-----------------------------"
	echo "This will create an archboot container for an archboot image."
	echo "Usage: ${_BASENAME} <directory> <options>"
	echo " Options:"
	echo "  -cc    Cleanup container eg. remove manpages, includes ..."
	echo "  -cp    Cleanup container package cache"
	echo "  -lf    add linux-firmware to container"
	echo "  -alf   add archboot-linux-firmware to container"
	exit 0
}

[[ -z "${1}" ]] && usage

_DIR="$1"

while [ $# -gt 0 ]; do
	case ${1} in
		-cc|--cc) _SAVE_RAM="1" ;;
		-cp|--cp) _CLEANUP_CACHE="1" ;;
		-lf|--lf) _LINUX_FIRMWARE="linux-firmware" ;;
		-alf|-alf) _LINUX_FIRMWARE="archboot-linux-firmware" ;;
        esac
	shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi


# prepare pacman dirs
mkdir -p "${_DIR}"/var/lib/pacman
mkdir -p "${_CACHEDIR}"
[[ -e "${_DIR}/proc" ]] || mkdir -m 555 "${_DIR}/proc"
[[ -e "${_DIR}/sys" ]] || mkdir -m 555 "${_DIR}/sys"
[[ -e "${_DIR}/dev" ]] || mkdir -m 755 "${_DIR}/dev"
# mount special file systems to ${_DIR}
mount --make-runbindable /sys/fs/cgroup
mount --make-runbindable /proc/sys/fs/binfmt_misc
mount --rbind "/proc" "${_DIR}/proc"
mount --rbind "/sys" "${_DIR}/sys"
mount --rbind "/dev" "${_DIR}/dev"
# install archboot
pacman --root "${_DIR}" -Sy base archboot --noconfirm --cachedir "${_PWD}"/"${_CACHEDIR}"
# umount special file systems
umount -R "${_DIR}/proc"
umount -R "${_DIR}/sys"
umount -R "${_DIR}/dev"
mount --make-rshared /sys/fs/cgroup
mount --make-rshared /proc/sys/fs/binfmt_misc
# generate locales
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US ISO-8859-1' >> /etc/locale.gen"
systemd-nspawn -D "${_DIR}" /bin/bash -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
systemd-nspawn -D "${_DIR}" locale-gen
# generate pacman keyring
systemd-nspawn -D "${_DIR}" pacman-key --init
systemd-nspawn -D "${_DIR}" pacman-key --populate archlinux
# copy local mirrorlist to container
cp /etc/pacman.d/mirrorlist "${_DIR}"/etc/pacman.d/mirrorlist
# only copy from archboot pacman.conf, else use default file
[[ "$(cat /etc/hostname)" == "archboot" ]] && cp /etc/pacman.conf "${_DIR}"/etc/pacman.conf
# disable checkspace option in pacman.conf, to allow to install packages in environment
sed -i -e 's:^CheckSpace:#CheckSpace:g' "${_DIR}"/etc/pacman.conf
# enable parallel downloads
sed -i -e 's:^#ParallelDownloads:ParallelDownloads:g' "${_DIR}"/etc/pacman.conf
# enable [testing] if enabled in host
if [[ "$(grep "^\[testing" /etc/pacman.conf)" ]]; then
    sed -i -e '/^#\[testing\]/ { n ; s/^#// }' ${_DIR}/etc/pacman.conf
    sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' ${_DIR}/etc/pacman.conf
    sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' ${_DIR}/etc/pacman.conf
fi
# install firmware package
[[ ! -z ${_LINUX_FIRMWARE} ]] && systemd-nspawn -D "${_DIR}" pacman -Sy "${_LINUX_FIRMWARE}" --noconfirm

if [[ "${_SAVE_RAM}" ==  "1" ]]; then
    # clean container from not needed files
    rm -r "${_DIR}"/usr/include
    rm -r "${_DIR}"/usr/share/{man,doc}
fi

if [[ "${_CLEANUP_CACHE}" ==  "1" ]]; then
    # clean cache
    rm -r "${_DIR}"/var/cache/pacman
fi
