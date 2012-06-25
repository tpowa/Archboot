Archboot release directory:
- This directory contains installation images based on archboot scripts.
- Those files are no official Arch Linux releases.
- Use them on your own risk.

Latest Releases:
- Hybrid image file and torrent is provided, 
  which include i686 and x86_64 core repository. 
- Please read the according Changelog files for RAM limitations.
- Please check md5sum before using it.
  http://www.archlinux.de/?page=GetFileFromMirror;file=iso/archboot/latest

Burning Release:
Hybrid image file is a standard CD-burnable image and also a raw disk image. 
- Can be burned to CD(RW) media using most CD-burning utilities. 
- Can be raw-written to a drive using 'dd' or similar utilities. 
  This method is intended for use with USB thumb drives.
  'dd if=<imagefile> of=/dev/<yourdevice> bs=1M'

Known Issues  and limitations:
- Release specific known issues and workarounds are posted in changelog files.
- dmraid might be broken on some boards, support is not perfect here.
  The reason is there are so many different hardware components out there.
  At the moment 1.0.0rc16 is included, with latest fedora patchset.
- grub cannot detect correct bios boot order.
  It may happen that hd(x,x) entries are not correct,
  thus first reboot may not work. 
  Reason: grub cannot detect bios boot order. 
  Fix: Either change bios boot order or change menu.lst to correct entries
  after successful boot.
  This cannot be fixed it's a restriction in grub!

What is the difference to the official install media (latest version)?
- It runs a modified Arch Linux system in initramfs.
- It is restricted to RAM usage, everything which is not necessary like
  man pages etc. is not provided.
- LTS kernel boot images are provided
- Initial module loading and hardware detection is done by the hwdetect script.
- It doesn't mount anything during boot process.
- It uses a different setup script.

Setup features (latest version):
- CD/USB/OTHER and FTP/HTTP installation mode
- Changing keymap and consolefont
- Changing time and date
- Preparing harddisk, like auto-prepare, partitioning, GUID (gpt) support etc.
- Creation of software raid/raid partitions, lvm2 devices and 
  luks encrypted devices
- Supports standard linux,raid/raid_partitions,dmraid,lvm2 and encrypted devices
- Filesystem support: ext2/3/4,btrfs,reiserfs,xfs,jfs,ntfs-3g,vfat
- Package selection support
- Autoaddition of usefull packages, like ntfs-3g etc.
- LTS kernel support
- Auto/Preconfiguration of fstab, mkinitcpio.conf, rc.conf,
  crypttab and mdadm.conf
- Auto/Preconfiguration of KMS/framebuffers
- Configuration of basic system files
- Setting root password
- grub-bios, lilo, extlinux/syslinux, grub-efi-x86_64, grub-efi-i386, refind-efi-x86_64 bootloader support

Bugs:
- If you find a bug, please mail the archboot developer directly.
- Arch Linux Bugtracker:
  http://bugs.archlinux.org

What is archboot?
- Archboot is a set of scripts to generate bootable media for CD/USB/PXE.
- It is designed for installation or rescue operation.
- It only runs in RAM, without any special filesystems like squashfs,
  thus it is limited to the RAM which is installed in your system.
  Please read the according Changelog files for RAM limitations.
- Git repository: 
  http://projects.archlinux.org/?p=archboot.git;a=summary
- It is developed by tpowa.

Have fun!
tpowa
<tpowa <funnysign> archlinux.org>
(archboot developer)
