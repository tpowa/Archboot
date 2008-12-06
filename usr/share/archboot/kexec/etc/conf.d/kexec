#
# Configuration for Kexec
#

# Path to kernel, default to stock arch kernel
KPATH="/mnt/boot/kernel26"

# Root partition
# The default attempts to autodetect
ROOTPART="$(mount | grep "on /mnt type" | cut -d' ' -f 1)"

# Additional kernel parameters
KPARAM="ro"

# Path to initrd image, default to stock arch kernel
INITRD="/mnt/boot/kernel26.img"
