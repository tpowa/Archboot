What is archboot?
- Archboot is a set of scripts to generate bootable media for CD/USB/PXE.
- It is designed for installation or rescue operation.
- It only runs in RAM, without any special filesystems like squashfs,
  thus it is limited to the RAM which is installed in your system.
  Please read the according Changelog files for RAM limitations.
- Git repository: 
  https://projects.archlinux.org/?p=archboot.git;a=summary
- It is developed by tpowa.

Latest Releases:
- Hybrid image file and torrent is provided, 
  which include i686 and x86_64 core repository.
- Hybrid ftp image file and torrent is provided, 
  which do not include i686 and x86_64 core repository.
- Please read the according Changelog files for RAM limitations.
- Please check md5sum before using it.
  https://downloads.archlinux.de/iso/archboot/latest

Burning Release:
Hybrid image file is a standard CD-burnable image and also a raw disk image. 
- Can be burned to CD(RW)/DVD media using most CD-burning utilities. 
- Can be raw-written to a drive using 'dd' or similar utilities. 
  This method is intended for use with USB thumb drives.
  'dd if=<imagefile> of=/dev/<yourdevice> bs=1M'

Supported boot modes of Archboot media:
- It supports BIOS booting with syslinux.
- It supports UEFI booting with gummiboot and EFISTUB.
- It supports Secure Boot with prebootloader.
- It supports grub(2)'s iso loopback support.
  variables used (below for example):
  iso_loop_dev=PARTUUID=XXXX
  iso_loop_path=/blah/archboot.iso
- It supports booting using syslinux's memdisk (only in BIOS mode).

The difference to the archiso install media:
- It provides an additional interactive setup and quickinst script.
- It contains [core] repository on media.
- It runs a modified Arch Linux system in initramfs.
- It is restricted to RAM usage, everything which is not necessary like
  man or info pages etc. is not provided.
- It doesn't mount anything during boot process.
- It supports remote installation through ssh.

Interactive setup features:
- Media and Network installation mode
- Changing keymap and consolefont
- Changing time and date
- Setup network with netctl
- Preparing storage disk, like auto-prepare, partitioning, 
  GUID (gpt) support, 4k sector drive support etc.
- Creation of software raid/raid partitions, lvm2 devices 
  and luks encrypted devices
- Supports standard linux,raid/raid_partitions,dmraid,lvm2
  and encrypted devices
- Filesystem support: ext2/3/4, btrfs, f2fs, nilfs2, reiserfs,xfs,jfs,
  ntfs-3g,vfat
- Name scheme support: PARTUUID, PARTLABEL, FSUUID, FSLABEL and KERNEL
- Mount support of grub(2) loopback and memdisk installation media
- Package selection support
- Signed package installation
- hwdetect script is used for preconfiguration
- Auto/Preconfiguration of framebuffer, uvesafb, kms mode, fstab,
  mkinitcpio.conf, systemd, crypttab and mdadm.conf
- Configuration of basic system files
- Setting root password
- grub(2) (BIOS and UEFI), refind-efi, gummiboot,
  syslinux (BIOS and UEFI) bootloader support

FAQ, Known Issues and limitations:
- Release specific known issues and workarounds are posted in changelog files.
- Check also the forum threads for posted fixes and workarounds.
- Why screen stays blank or other weird screen issues happen?
  Some hardware doesn't like the KMS activation, 
  use nouveau.modeset=0 or radeon.modeset=0 or i915.modeset=0 or nomodeset on boot prompt.
- dmraid might be broken on some boards, support is not perfect here.
  The reason is there are so many different hardware components out there. 
  At the moment 1.0.0rc16 is included, with latest fedora patchset.
- Why is parted used in setup routine, instead of cfdisk in 
  msdos partitiontable mode?
  - parted is the only linux partition program that can handle all type of 
    things the setup routine offers.
  - cfdisk cannot handle GPT/GUID nor it can allign partitions correct 
    with 1MB spaces for 4k sector disks.
  - cfdisk is a nice tool but is too limited to be the standard 
    partitioner anymore.
  - cfdisk is still included but has to be run in an other terminal.

Bugs:
- If you find a bug, please mail the archboot developer directly.
- Arch Linux Bugtracker:
  https://bugs.archlinux.org

Have fun!
tpowa
<tpowa <funnysign> archlinux.org>
(archboot developer)
