#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/update-installer.sh

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) _D_SCRIPTS="1" ;;
		-latest|--latest) _L_COMPLETE="1" ;;
		-latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
		-latest-image|--latest-image) _G_RELEASE="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

_archboot_check
_download_latest
echo -e "\033[1mInformation:\033[0m Logging is done on \033[1m/dev/tty7\033[0m ..."

# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    _update_installer_check
    touch /.update-installer
    # disable kernel messages on aarch64
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && echo 0 >/proc/sys/kernel/printk
    _umount_w_dir
    _zram_mount "${_ZRAM_SIZE}"
    echo -e "\033[1mStep 1/9:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    echo -e "\033[1mStep 2/9:\033[0m Waiting for gpg pacman keyring import to finish ..."
    _gpg_check
    echo -e "\033[1mStep 3/9:\033[0m Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    _create_container || exit 1
    echo -e "\033[1mStep 4/9:\033[0m Moving kernel ${VMLINUZ} to /${VMLINUZ} ..."
    mv "${_W_DIR}"/boot/${VMLINUZ} / || exit 1
    _kver
    echo -e "\033[1mStep 5/9:\033[0m Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/share/archboot/patches/31-mkinitcpio.fixed "${_W_DIR}"/usr/bin/mkinitcpio
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    # write initramfs to "${_W_DIR}"/tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    #mv "${_W_DIR}/tmp" /initrd || exit 1
    echo -e "\033[1mStep 6/9:\033[0m Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    # 10 seconds for getting free RAM
    sleep 10
    echo -e "\033[1mStep 7/9:\033[0m Create initramfs /initrd.img ..."
    echo "          This will need some time ..."
    _create_initramfs
    echo -e "\033[1mStep 8/9:\033[0m Cleanup ${_W_DIR} ..."
    cd /
    _umount_w_dir
    # unload virtio-net to avoid none functional network device on aarch64
    cat /proc/modules | grep -qw virtio_net && rmmod virtio_net
    echo -e "\033[1mStep 9/9:\033[0m Loading files through kexec into kernel now ..."
    _kexec
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    _ZRAM_IMAGE_SIZE=${_ZRAM_IMAGE_SIZE:-"5G"}
    _zram_mount "${_ZRAM_IMAGE_SIZE}"
    echo -e "\033[1mStep 1/2:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    echo -e "\033[1mStep 2/2:\033[0m Generating new iso files in ${_W_DIR} now ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mFinished:\033[0m New isofiles are located in ${_W_DIR}"
fi
