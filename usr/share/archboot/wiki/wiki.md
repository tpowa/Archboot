<span dir="">[![Logo](https://pkgbuild.com/~tpowa/archboot/web/logo.png)]() </span>

<span dir="">[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=Z7GXKW4MKHK7C) You like the project? I like coffee :smile:</span>

**Table of contents**

[[_TOC_]]

## Introduction

**Archboot**<span dir=""> is a most advanced, modular [**Arch Linux**](https://archlinux.org/) boot/install image creation utility to generate reproducible bootable media for CD/USB/PXE, designed for installation or rescue operation. It is fully based on </span>[**mkinitcpio**](https://wiki.archlinux.org/title/Mkinitcpio "Mkinitcpio")<span dir="">, only runs in RAM and without any special filesystems like squashfs/erofs.</span>\
<span dir="">The project is developed by </span>[**tpowa**](https://archlinux.org/people/developers/#tpowa)<span dir=""> since 2006.</span>

## <span dir="">Image Releases</span>

* **Release schedule**: on 10th, 20th and 30th of a month new images are released.
* [**Hybrid image files**](https://wiki.syslinux.org/wiki/index.php?title=Isohybrid), [**kernel**](https://wiki.archlinux.org/title/Kernel "Kernel") and [**initrds**](https://wiki.archlinux.org/title/Initrd "Initrd") are provided.
* **PGP KEY**: [**5B7E 3FB7 1B7F 1032 9A1C 03AB 771D F662 7EDF 681F**](https://keyserver.ubuntu.com/pks/lookup?op=vindex&fingerprint=on&exact=on&search=0x5B7E3FB71B7F10329A1C03AB771DF6627EDF681F) for file verification is provided.

### **<span dir="">Download image files</span>**

* Image files are released [**here**](https://pkgbuild.com/\~tpowa/archboot/iso/).
* Source packages with archboot repository are located [**here**](https://pkgbuild.com/\~tpowa/archboot/src/iso/).
* Latest news about the package itself, are posted [**here**](https://www.reddit.com/r/archboot/).

#### **<span dir="">[**Arch Linux ARM aarch64**](https://archlinuxarm.org/)</span>**
| Release information | ISO images | SHA256SUM | Forum thread |
|---------------------|------------|-----------|--------------|
| [**Latest**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/Release.txt) | [**Download**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest) | [**Check**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/sha256sum.txt) | [**Forum link**](https://archlinuxarm.org/forum/viewtopic.php?f=8&t=15777) |
* Supports Apple Mac M1 and higher for virtual machines eg. [**Parallels Desktop**](https://wiki.archlinux.org/title/Parallels_Desktop "Parallels Desktop"), [**UTM**](https://mac.getutm.app/ "UTM MacOS") and [**VMware**](https://wiki.archlinux.org/title/VMware "VMware")

#### **<span dir="">[**Arch Linux RISC-V riscv64**](https://archriscv.felixc.at/)</span>**
| Release information | ISO images | SHA256SUM |
|---------------------|------------|-----------|
| [**Latest**](https://pkgbuild.com/\~tpowa/archboot/iso/riscv64/latest/Release.txt) | [**Download**](https://pkgbuild.com/\~tpowa/archboot/iso/riscv64/latest) | [**Check**](https://pkgbuild.com/\~tpowa/archboot/iso/riscv64/latest/sha256sum.txt)

#### **<span dir="">[**Arch Linux x86_64**](https://archlinux.org/)</span>**
| Release information | ISO images | SHA256SUM | Forum thread |
|---------------------|------------|-----------|--------------|
| [**Latest**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/Release.txt) | [**Download**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest) | [**Check**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/sha256sum.txt) | [**Forum link**](https://bbs.archlinux.org/viewtopic.php?id=182439) |

### **<span dir="">Features of the images</span>**
| Type | RAM to boot | WiFi support | LAN support | Package cache for installation | Size AARCH64 | Size RISCV64 | Size X86_64 |
|------|-------------|--------------|-------------|--------------------------------|--------------|--------------|---------------|
| _date_-latest | 2000MB | No | DHCP server needed | Yes | 134 MB || 131MB |
| _date_ | 1300MB | Yes | Yes | No | 350MB | 457MB | 448MB |
| _date_-local | 3300MB | Yes | Yes | Yes | 1210MB|| 1485MB |

* **With** a fast internet connection **and** a running [**DHCP**](https://wiki.archlinux.org/title/DHCP "DHCP") server, go for the **"latest"** image.
* **Without** an internet connection for installation, you should use the **"local"** image. It includes a **local package repository** for installation.

### [**<span dir="">PXE</span>**](https://wiki.archlinux.org/title/PXE "PXE") **<span dir="">booting / Rescue system</span>**
| Download | AARCH64 | RISCV64 | X86_64 |
|----------|--------|---------|---------|
| Kernel | [**vmlinuz_archboot_aarch64**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/vmlinuz_archboot_aarch64) | [**vmlinuz_archboot_riscv64**](https://pkgbuild.com/\~tpowa/archboot/iso/riscv64/latest/boot/vmlinuz_archboot_riscv64) |[**vmlinuz_archboot_x86_64**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/vmlinuz_archboot_x86_64)  |
| Initrd | [**initramfs_aarch64.img**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/initramfs_aarch64.img)<br>[**initramfs_aarch64-latest.img**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/initramfs_aarch64-latest.img)<br>[**initramfs_aarch64-local-0.img**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/initramfs_aarch64-local-0.img)<br>[**initramfs_aarch64-local-1.img**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/initramfs_aarch64-local-1.img) |[**initramfs_riscv64.img**](https://pkgbuild.com/\~tpowa/archboot/iso/riscv64/latest/boot/initramfs_riscv64.img) | [**initramfs_x86_64.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/initramfs_x86_64.img)<br>[**initramfs_x86_64-latest.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/initramfs_x86_64-latest.img)<br>[**initramfs_x86_64-local-0.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/initramfs_x86_64-local-0.img)<br>[**initramfs_x86_64-local-1.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/initramfs_x86_64-local-1.img) |
| Microcode | [**amd-ucode.img**](https://pkgbuild.com/\~tpowa/archboot/iso/aarch64/latest/boot/amd-ucode.img) || [**intel-ucode.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/intel-ucode.img)<br>[**amd-ucode.img**](https://pkgbuild.com/\~tpowa/archboot/iso/x86_64/latest/boot/amd-ucode.img) |

* For [**PXE**](https://wiki.archlinux.org/title/PXE "PXE") booting add the [**kernel**](https://wiki.archlinux.org/title/Kernel "Kernel"),[**initrds**](https://wiki.archlinux.org/title/Initrd "Initrd") and [**microcode**](https://wiki.archlinux.org/title/Microcode "Microcode") to your [**TFTP**](https://wiki.archlinux.org/title/TFTP "TFTP"), add `rootfstype=ramfs` to your [**kernel command line**](https://wiki.archlinux.org/title/Kernel_command_line "Kernel command line") setup and you will get a running installation/rescue system.
* For rescue booting add an entry to your [**bootloader**](https://wiki.archlinux.org/title/Bootloader "Bootloader") pointing to the [**kernel**](https://wiki.archlinux.org/title/Kernel "Kernel"), [**initrds**](https://wiki.archlinux.org/title/Initrd "Initrd"),[**microcode**](https://wiki.archlinux.org/title/Microcode "Microcode") and add `rootfstype=ramfs` to your [**kernel command line**](https://wiki.archlinux.org/title/Kernel_command_line "Kernel command line").
* For **local image** download **both** initrds and load **both** files with your bootloader or PXE setup.

### **<span dir="">Supported boot modes</span>**
| Boot Mode | AARCH64 | RISCV64 | X86_64 |
|-----------|---------|---------|--------|
| [**MBR**](https://wiki.archlinux.org/title/MBR "MBR") BIOS with [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB") | No | No | Yes |
| [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI")/UEFI_CD booting with [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB") | Yes | No | Yes |
| UEFI_MIX_MODE booting with [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB") | No | No | Yes |
| [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot") with the<br>included fedora [**signed shim**](https://wiki.archlinux.org/title/Secure_Boot#shim "Secure Boot") | Yes | No | Yes |
| [**MBR**](https://wiki.archlinux.org/title/MBR "MBR") with [**U-Boot**](https://www.denx.de/wiki/U-Boot "U-Boot")  | No | Yes | No |

It supports [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB")'s iso loopback support. Variables used (below for example):

```plaintext
iso_loop_dev=PARTUUID=12345678-1234-1234-1234-123456789ABC
iso_loop_path=/dirname/basename_of_archboot.iso
```

With [**GPT**](https://wiki.archlinux.org/title/GPT "GPT"), the PARTUUID can be obtained from the `Partition unique GUID` line of the `sgdisk --info=y /dev/sdx` command output.

```plaintext
menuentry "Archboot" --class iso {
loopback loop (hdX,Y)/archboot.iso
linux (loop)/boot/vmlinuz_x86_64 iso_loop_dev=/dev/sdXY iso_loop_path=/archboot.iso
initrd (loop)/boot/initramfs_x86_64.img
}
```

### **<span dir="">Burning release or writing to disk</span>**

Hybrid image file is a standard CD/DVD-burnable image and also a raw disk image.

* Can be burned to CD/DVD(RW) media using most [**CD Burning**](https://wiki.archlinux.org/title/CD_Burning "CD Burning") utilities.
* Can be raw-written to a drive using 'dd' or similar utilities. This method is intended for use with USB thumb drives.

```plaintext
# dd if=imagefile of=/dev/yourdevice bs=1M
```

[**Rufus for Windows**](https://rufus.ie "Rufus for Windows"): Use dd-Mode to write the image on Windows.

### **<span dir="">Installation with a graphical environment or VNC instead of plain console</span>**

* During boot all network interfaces will try to obtain an IP address through [**dhcpcd**](https://wiki.archlinux.org/title/Dhcpcd "Dhcpcd").
* If your network does not obtain an address, please setup the [**network**](https://wiki.archlinux.org/title/Network "Network") manually or with the setup routine.

#### **<span dir="">Preconfigured environments</span>**
| Desktop<br>Environment | Command Switch |
|------------------------|----------------|
| [**Gnome**](https://wiki.archlinux.org/title/Gnome "Gnome") | `# update-installer -gnome` |
| [**Gnome**](https://wiki.archlinux.org/title/Gnome "Gnome") [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland") | `# update-installer -gnome-wayland` |
| [**KDE Plasma**](https://wiki.archlinux.org/title/KDE_Plasma "KDE Plasma") | `# update-installer -plasma` |
| [**KDE Plasma**](https://wiki.archlinux.org/title/KDE_Plasma "KDE Plasma") [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland") | `# update-installer -plasma-wayland` |
| [**Xfce**](https://wiki.archlinux.org/title/Xfce "Xfce") | `# update-installer -xfce` |

* [**VNC**](https://wiki.archlinux.org/title/VNC "VNC") is automatically launched with starting [**Xorg**](https://wiki.archlinux.org/title/Xorg "Xorg").
  * Connect with your vnc client and use password:**archboot**
  * [**Edit**](https://wiki.archlinux.org/title/Edit "Edit") `/etc/archboot/defaults` to change default vnc password.
* On [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland") [**VNC**](https://wiki.archlinux.org/title/VNC "VNC") is **not** available.

#### **<span dir="">Custom environment without VNC support</span>**

##### <span dir="">Xorg</span>

* [**Edit**](https://wiki.archlinux.org/title/Edit "Edit") `/etc/archboot/defaults` and change _`CUSTOM`_`XORG array` to your needs.
* Run: `# update-installer -custom-xorg` from a console login

##### <span dir="">Wayland</span>

* [**Edit**](https://wiki.archlinux.org/title/Edit "Edit") `/etc/archboot/defaults` and change _`CUSTOM`_`WAYLAND array` to your needs.
* Run: `# update-installer -custom-wayland` from a console login

### **<span dir="">Remote installation with OpenSSH</span>**

* During boot all network interfaces will try to obtain an IP address through [**dhcpcd**](https://wiki.archlinux.org/title/Dhcpcd "Dhcpcd").
* root [**password**](https://wiki.archlinux.org/title/Password "Password") is **not** set by default! If you need privacy during installation set a [**password**](https://wiki.archlinux.org/title/Password "Password").

```plaintext
$ ssh root@yourip
```

### **<span dir="">Secure Boot support with shim package signed from fedora</span>**

* **Caveat:**
  * This method is intended to use for [**dual booting**](https://wiki.archlinux.org/title/Dual_boot "Dual boot") with Windows, without losing the Secure Boot benefits for Windows.
  * This method will **not** make your system **more** secure.
  * It installs a bootloader which is **not** controlled by Arch Linux and **breaks** the concept of **Secure Boot** as is.
* Please read [**Roderick Smith's guide**](https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim) first for initial shim setup.
* In order to boot in [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot") mode on first boot:
  * you need to enroll archboot's MOK key from disk: `/EFI/KEY/MOK.cer`
* Tools included for key management: KeyTool, HashTool, mokutil, sbsigntools, sbctl and mkkeys.sh
* setup script supports the following [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot") layout:
  * shim from fedora is copied
  * creating new keys is supported
  * using existing keys from `/etc/secureboot/keys` in layout secureboot-keys.sh produces
  * MOK setup is done with keys
  * adding pacman hook for automatic signing
  * On first reboot you need to enroll the used keys to the MOK then your installed system is dual boot ready.
* It has a support script for creating your own keys and backup the existing keys, which already include the 2 needed Microsoft certificates:

```plaintext
# secureboot-keys.sh -name=yournametoembed directory
```
### **<span dir="">Switch to full Arch Linux system</span>**
* The Archboot system is stripped down to minimal space usage, though man/info pages, includes, additional kernel modules (eg. sound) and other things are not provided by default.
* If you need the full Arch Linux system launch: `# update-installer -full-system`
* This will also stop cleaning the system, while running other `# update-installer` tasks.

### **<span dir="">Interactive setup</span>**

You can run each point for doing the mentioned task. If you do a fresh install, it is recommended to run each point in the order as presented.

#### **<span dir="">Changing keymap and console fonts</span>**

* Your [**keymap**](https://wiki.archlinux.org/title/Keymap "Keymap") and [**console fonts**](https://wiki.archlinux.org/title/Console_fonts "Console fonts") will be set by km script.

#### **<span dir="">Setup network</span>**

* Your [**network**](https://wiki.archlinux.org/title/Network "Network") will be configured by [**netctl**](https://wiki.archlinux.org/title/Netctl "Netctl").

#### **<span dir="">Select Source</span>**

* Local mode:
  * Local package database is autodetected
* Online mode:
  * Latest [**pacman**](https://wiki.archlinux.org/title/Pacman "Pacman") [**mirrors**](https://wiki.archlinux.org/title/Mirror "Mirror") will be synced and you have to select your favourite mirror.
  * You will be asked if you want to activate the [**testing**](https://wiki.archlinux.org/title/Testing "Testing") repository.
  * You can decide to load the latest archboot environment and cache packages for installation.

#### **<span dir="">Changing timezone and date</span>**

* You set your [**timezone**](https://wiki.archlinux.org/title/Timezone "Timezone") and [**date**](https://wiki.archlinux.org/title/Date "Date") with the tz script.

#### **<span dir="">Prepare Storage drive</span>**

* You setup your storage drive, [**filesystems**](https://wiki.archlinux.org/title/Filesystems "Filesystems") and define your mountpoints.
* auto-prepare mode, manual [**partitioning**](https://wiki.archlinux.org/title/Partitioning "Partitioning"), [**GUID**](https://wiki.archlinux.org/title/GUID "GUID") (gpt) support, [**MBR**](https://wiki.archlinux.org/title/MBR "MBR") (bios) support, [**Advanced Format**](https://wiki.archlinux.org/title/Advanced_Format "Advanced Format") 4k sector drive support etc.
* Creation of software [**RAID**](https://wiki.archlinux.org/title/RAID "RAID")/[**RAID**](https://wiki.archlinux.org/title/RAID "RAID") partitions, [**LVM**](https://wiki.archlinux.org/title/LVM "LVM") devices and [**LUKS**](https://wiki.archlinux.org/title/LUKS "LUKS") encrypted devices
* Supports standard linux,[**RAID**](https://wiki.archlinux.org/title/RAID "RAID")/[**RAID**](https://wiki.archlinux.org/title/RAID "RAID")\_partitions,dmraid/[**fakeraid**](https://wiki.archlinux.org/title/Fakeraid "Fakeraid"),[**LVM**](https://wiki.archlinux.org/title/LVM "LVM") and [**LUKS**](https://wiki.archlinux.org/title/LUKS "LUKS") encrypted devices
* Filesystem support: ext2/[**ext3**](https://wiki.archlinux.org/title/Ext3 "Ext3")/[**ext4**](https://wiki.archlinux.org/title/Ext4 "Ext4"), [**btrfs**](https://wiki.archlinux.org/title/Btrfs "Btrfs"), [**F2FS**](https://wiki.archlinux.org/title/F2FS "F2FS"), nilfs2, [**XFS**](https://wiki.archlinux.org/title/XFS "XFS"), [**JFS**](https://wiki.archlinux.org/title/JFS "JFS"), [**VFAT**](https://wiki.archlinux.org/title/VFAT "VFAT")
* [**Persistent block device naming**](https://wiki.archlinux.org/title/Persistent_block_device_naming "Persistent block device naming") support: [**PARTUUID**](https://wiki.archlinux.org/title/PARTUUID "PARTUUID"), [**PARTLABEL**](https://wiki.archlinux.org/title/PARTLABEL "PARTLABEL"), UUID, LABEL and KERNEL

#### **<span dir="">Install Packages</span>**

* You can modify the packages to install in `/etc/archboot/defaults`.
* [**Pacman**](https://wiki.archlinux.org/title/Pacman "Pacman") will install the packages for the first boot to your storage drive.

#### **<span dir="">Configure System</span>**

* hwdetect script is used for preconfiguration
* Auto/Preconfiguration of [**fstab**](https://wiki.archlinux.org/title/Fstab "Fstab"), [**KMS**](https://wiki.archlinux.org/title/KMS "KMS") mode, [**SSD**](https://wiki.archlinux.org/title/SSD "SSD"), [**mkinitcpio.conf**](https://wiki.archlinux.org/title/Mkinitcpio.conf "Mkinitcpio.conf"), [**systemd**](https://wiki.archlinux.org/title/Systemd "Systemd"), [**crypttab**](https://wiki.archlinux.org/title/Crypttab "Crypttab") and [**mdadm**](https://wiki.archlinux.org/title/Mdadm "Mdadm").conf
* You will be asked to copy the [**pacman**](https://wiki.archlinux.org/title/Pacman "Pacman") GPG keyring to the installed system
* Configuration of basic system files: [**hostname**](https://wiki.archlinux.org/title/Hostname "Hostname"),[**Linux console**](https://wiki.archlinux.org/title/Linux_console "Linux console"),[**locale.conf**](https://wiki.archlinux.org/title/Locale.conf "Locale.conf"),[**fstab**](https://wiki.archlinux.org/title/Fstab "Fstab"),[**mkinitcpio.conf**](https://wiki.archlinux.org/title/Mkinitcpio.conf "Mkinitcpio.conf"),[**modprobe.conf**](https://wiki.archlinux.org/title/Modprobe.conf "Modprobe.conf"),[**resolv.conf**](https://wiki.archlinux.org/title/Resolv.conf "Resolv.conf"),[**hosts**](https://wiki.archlinux.org/title/Hosts "Hosts"),[**Locale**](https://wiki.archlinux.org/title/Locale "Locale"),[**mirrors**](https://wiki.archlinux.org/title/Mirrors "Mirrors"),[**pacman.conf**](https://wiki.archlinux.org/title/Pacman.conf "Pacman.conf")
* Setting root [**password**](https://wiki.archlinux.org/title/Password "Password")

#### **<span dir="">Install Bootloader</span>**

* You setup your preferred [**bootloader**](https://wiki.archlinux.org/title/Bootloader "Bootloader") from this menu point.
* [**GPT**](https://wiki.archlinux.org/title/GPT "GPT") [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI") supported bootloaders: [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB"), [**refind-efi**](https://wiki.archlinux.org/title/Refind-efi "Refind-efi"), [**systemd-boot**](https://wiki.archlinux.org/title/Systemd-boot "Systemd-boot")
* [**MBR**](https://wiki.archlinux.org/title/MBR "MBR") BIOS supported bootloaders: [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB")
* [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot") supports only shim signed by fedora with [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB")
* The selected [**bootloader**](https://wiki.archlinux.org/title/Bootloader "Bootloader") will be installed to your system and you can modify the configuration file afterwards.

### **<span dir="">For experts: quickinst installation</span>**

* This script is for **experts**, who assemble the filesystems first and mount them in a directory.
* **quickinst** will autodetect the packages to install for a minimal system.

```plaintext
# quickinst <directory>
```

### **<span dir="">Keep your image up to date</span>**

* You can always bump your image to **latest** available possibilities (see `-h` flag for all the options).

```plaintext
# update-installer <option>
```

### **<span dir="">Tools for backup and copying of an existing system</span>**

Archboot provides 2 additional scripts for doing those tasks.

* internal backup / copying you can use:

```plaintext
# copy-mountpoint.sh
```

* internal or external [**backup**](https://wiki.archlinux.org/title/Backup "Backup") / copying with rsync you can use:

```plaintext
# rsync-backup.sh
```

### **<span dir="">Restoring an USB device to FAT32 state</span>**

* When you have used the .iso image to create an USB installer, your USB stick is no longer useful for anything else.
* Any remaining space on the stick (supposing you used a larger-than the .img file) is inaccessible.
* Fortunately, it is easy to re-create a FAT32 partition on the stick so that the USB stick again becomes available for carrying around your data.
* Check carefully which device actually is your USB stick. **The next command will render all data on a device inaccessible**:

```plaintext
# restore-usbstick.sh device
```

### **<span dir="">FAQ, Known Issues and limitations</span>**

* Please check the forum threads for posted fixes and workarounds.
* Please run this script to get latest fixes from git:

```plaintext
# update-installer -u
```

* Package XYZ is missing in archboot environment.

<dl>
<dd>

<dl>
<dd>

[**Install**](https://wiki.archlinux.org/title/Install "Install") the missing package as needed.

</dd>
<dd>

For example, [**archinstall**](https://wiki.archlinux.org/title/Archinstall "Archinstall") is not included by default since it needs python3 which is a large dependency.

</dd>
</dl>

</dd>
</dl>

* The **screen stays blank** or other **weird screen issues** happen?

<dl>
<dd>

<dl>
<dd>

Some hardware does not like the [**KMS**](https://wiki.archlinux.org/title/KMS "KMS") activation, use `radeon.modeset=0`, `i915.modeset=0`, `amdgpu.modeset=0` or `nouveau.modeset=0` on boot prompt.

</dd>
</dl>

</dd>
</dl>

* Your system **hangs** during the **boot process**?

<dl>
<dd>

<dl>
<dd>

Any combinations of the [**kernel parameters**](https://wiki.archlinux.org/title/Kernel_parameters "Kernel parameters"): `noapic`, `nolapic`, `acpi=off`, `pci=routeirq`, `pci=nosmp` or `pci=nomsi` may be useful.

</dd>
</dl>

</dd>
</dl>

* dmraid/[**fakeraid**](https://wiki.archlinux.org/title/Fakeraid "Fakeraid") might be broken on some boards, support is not perfect here.

<dl>
<dd>

<dl>
<dd>The reason is there are so many different hardware components out there. At the moment 1.0.0rc16 is included, with latest fedora patchset, development has been stopped.</dd>
<dd>

mdadm supports some isw and ddf fakeraid chipsets, but assembling during boot is deactivated in `/etc/mdadm.conf`!

</dd>
</dl>

</dd>
</dl>

* [**GRUB**](https://wiki.archlinux.org/title/GRUB "GRUB") cannot detect correct bios boot order:

<dl>
<dd>

<dl>
<dd>It may happen that hd(x,x) entries are not correct, thus first reboot may not work.</dd>
<dd>Reason: grub cannot detect bios boot order.</dd>
<dd>Fix: Either change bios boot order or change menu.lst to correct entries after successful boot. This cannot be fixed it is a restriction in grub2!</dd>
</dl>

</dd>
</dl>

* [**efibootmgr**](https://wiki.archlinux.org/title/Efibootmgr "Efibootmgr") setup entries are not working:

<dl>
<dd>

<dl>
<dd>

It may happen that [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI") boot entries are not correct, thus first reboot may not work e.g. [**Ovmf**](https://wiki.archlinux.org/title/Ovmf "Ovmf") [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI") is affected by this.

</dd>
<dd>

Reason: The [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI") implementation does not support how setup created the [**efibootmgr**](https://wiki.archlinux.org/title/Efibootmgr "Efibootmgr") entries.

</dd>
<dd>

Fix: Add manual entries and delete wrong entries from your [**UEFI**](https://wiki.archlinux.org/title/UEFI "UEFI") implementation.

</dd>
</dl>

</dd>
</dl>

* Redisplay the **Welcome to Arch Linux** message:

<dl>
<dd>

<dl>
<dd>Reason: The Welcome to Arch Linux (archboot environment) message is displayed once, before the user takes any action.</dd>
<dd>

Fix: Switch to a virtual console (with `Alt+F1...F6`) you have not used so far or run `cat /etc/motd` from within a shell prompt.

</dd>
</dl>

</dd>
</dl>

* How much RAM is needed to boot?

<dl>
<dd>

<dl>
<dd>It's an initramdisk which includes everything. The calculated size to boot the image follows the formula:</dd>
<dd>initramdisk + kernelimage + unpackedinitramdisk = minimum RAM to boot</dd>
</dl>

</dd>
</dl>

* What is the difference to the [**archiso**](https://wiki.archlinux.org/title/Archiso "Archiso") install image?

<dl>
<dd>

<dl>
<dd>

| Feature | archboot | archiso |
|---------|----------|---------|
| Developers | tpowa | arch-releng team |
| [**archinstall**](https://wiki.archlinux.org/title/Archinstall "Archinstall") | Optional | Yes |
| setup/quickinst script | Yes | No |
| [**Arch Install Scripts**](https://wiki.archlinux.org/title/Arch_Install_Scripts "Arch Install Scripts") | Yes | Yes |
| [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot")<br>with Microsoft certificates<br>supported by fedora signed shim | Yes | No |
| Base system located on| initramfs | squashfs |
| Man/Info pages | Optional | Yes |
| Localization | Optional | Yes |
| [**accessibility**](https://wiki.archlinux.org/title/Accessibility "Accessibility") support | No | Yes |
| [**netctl**](https://wiki.archlinux.org/title/Netctl "Netctl") support | Yes | No |
| Mobile broadband modem<br>management service (modemmanager) | No | Yes |
| Text browser | [**elinks**](https://wiki.archlinux.org/title/Elinks "Elinks") | [**lynx**](https://wiki.archlinux.org/title/Lynx "Lynx") |
| IRC client | [**weechat**](https://wiki.archlinux.org/title/Weechat "Weechat") | [**irssi**](https://wiki.archlinux.org/title/Irssi "Irssi") |
| IRC and text browser preconfigured | Yes | No |
| [**Chromium**](https://wiki.archlinux.org/title/Chromium "Chromium") browser | Optional | No |
| [**Firefox**](https://wiki.archlinux.org/title/Firefox "Firefox") browser | Yes | No |
| [**Gnome**](https://wiki.archlinux.org/title/Gnome "Gnome") desktop | Yes | No |
| [**Gnome**](https://wiki.archlinux.org/title/Gnome "Gnome") [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland") | Yes | No |
| [**KDE/Plasma**](https://wiki.archlinux.org/title/KDE "KDE/Plasma") desktop | Yes | No |
| [**KDE/Plasma**](https://wiki.archlinux.org/title/KDE "KDE/Plasma") [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland") | Yes | No |
| [**Xfce**](https://wiki.archlinux.org/title/Xfce "Xfce") desktop | Yes | No |
| Internal update feature | Yes | No |
| Offline installation support | Yes | No |
| [**VNC**](https://wiki.archlinux.org/title/VNC "VNC") installation support | Yes | No |
| Image size | >131-1485MB | >833MB |
| RAM to boot | >1.3GB | >800MB |
| Bootup speed | 8 seconds | 23 seconds |
| Build speed | faster | slower |
| Image assembling | grub-mkrescue | xorriso |
| Image bootloader | [**grub**](https://wiki.archlinux.org/title/Grub "Grub") | [**grub**](https://wiki.archlinux.org/title/Grub "Grub") |
| Reproducibility | Yes | No |
| Easy custom live CD creation | No | Yes |

</dd>
</dl>

</dd>
</dl>

### **<span dir="">Screenshot gallery</span>**

Take a look at the archboot screenshot [**gallery**](https://pkgbuild.com/\~tpowa/archboot/web).

### **<span dir="">Development: GIT repository</span>**

GIT repository can be found at [**Arch Linux Gitlab**](https://gitlab.archlinux.org/tpowa/archboot) or [**Github**](https://github.com/tpowa/Archboot) .

### **<span dir="">Bugs</span>**

[**Bugtracker**](https://gitlab.archlinux.org/tpowa/archboot/-/issues)

## <span dir="">Create rescue system of running system</span>

* Create the initrd with your chosen profile:

```plaintext
# mkinitcpio -c /etc/archboot/yourwantedsystem.conf -g initrd.img
```

* Add your used kernel and initrd to your bootloader.

## <span dir="">Create image files</span>

### **<span dir="">Installation</span>**

* Add **archboot** repository to your **/etc/pacman.conf**:

```plaintext
[archboot]
Server = https://pkgbuild.com/~tpowa/archboot/pkg
```

* [**Install**](https://wiki.archlinux.org/title/Install "Install") the **archboot** package on **x86_64** hardware.

```plaintext
# pacman -Sy archboot
```

* [**Install**](https://wiki.archlinux.org/title/Install "Install") the **archboot-arm** package on **aarch64** hardware.

```plaintext
# pacman -Sy archboot-arm
```

* [**Install**](https://wiki.archlinux.org/title/Install "Install") the **archboot-riscv** package on **riscv64** hardware.

```plaintext
# pacman -Sy archboot-riscv
```

* You can build **aarch64** or **riscv64** images on **x86_64** hardware. [**Install**](https://wiki.archlinux.org/title/Install "Install") the **qemu-user-static** package.
```plaintext
# pacman -Sy qemu-user-static
```
* If you want to build **aarch64** or **riscv64** images replace **x86_64** with the architecture of your choice in the commands and files below.


### **<span dir="">Requirements</span>**

Around 3GB free space on disk

### **<span dir="">Create image files without modifications</span>**

#### **<span dir="">Building a new release</span>**

This script creates every installation media with latest available core/extra packages and boot/ directory with kernel and initrds.

```plaintext
# archboot-x86_64-release.sh directory
```

You get the images and boot/ files in _directory_.

#### **<span dir="">Rebuilding a release (reproducibility)</span>**

```plaintext
# archboot-x86_64-release.sh directory https://pkgbuild.com/~tpowa/archboot/src/iso/x86_64/latest/
```

You get the rebuild image and boot/ files in _directory_.

### **<span dir="">Create image files with modifications:</span>**

Explanation of the archboot image tools.

#### **<span dir="">archboot-x86_64-create-container.sh</span>**

This script will create an archboot container for image creation.

```plaintext
# archboot-x86_64-create-container.sh directory
```

You get an archboot container in _directory_.

To enter the container run:

```plaintext
# systemd-nspawn -D directory
```

Modify your container to your needs. Then run archboot-x86_64-iso.sh for image creation in container.

#### **<span dir="">archboot-x86_64-iso.sh</span>**

* Script for image creation from running system or for use in archboot container.
* For **normal image** creation run:

```plaintext
# archboot-x86_64-iso.sh -g
```

* **Latest image**: add `-p=x86_64-latest` to command above.
* **Local image**: add `-p=x86_64-local` to command above.

#### **<span dir="">Configuration files for image creation:</span>**

There are the following configuration files for ISO creation:

* `/etc/archboot/defaults` : defaults for packages, bootloader config and server setup.
* `/etc/archboot/presets/name` : presets for the images, defines which kernel and mkinitcpio.conf is used.
* `/etc/archboot/name.conf` : contains the HOOKS, which are used for the initramdisks.

## <span dir="">Setting up an archboot image server</span>

### **<span dir="">Configuration file</span>**

You need to configure all your settings in the configuration file: `/etc/archboot/defaults`.

### **<span dir="">Requirements</span>**

* You have a normal user, which has access to a working gpg setup with own signature.
* You have a normal user with ssh access to the server, on which the images should upload.
* Add the directories on the remote server, you want to upload to.

### **<span dir="">Running commands</span>**

#### **<span dir="">x86_64 architecture</span>**

Simple run:

```plaintext
# archboot-x86_64-server-release.sh
```

#### **<span dir="">aarch64/riscv64 architecture</span>**

* You have to skip the tarball creation step, on **aarch64** or **riscv64** hardware.
* [**Install**](https://wiki.archlinux.org/title/Install "Install") the [**<span dir="">qemu-user-static</span>**](https://archlinux.org/packages/?name=qemu-user-static) package, for building on **x86_64** hardware.
* On first time setup you need to create the pacman-aarch64-chroot tarball on **x86_64** hardware.

```plaintext
# archboot-pacman-aarch64-chroot.sh build-directory
# archboot-pacman-riscv64-chroot.sh build-directory
```

* Afterwards you only have to run for each release:

```plaintext
# archboot-aarch64-server-release.sh
# archboot-riscv64-server-release.sh
```

#### **<span dir="">Server cleanup</span>**

The `/etc/archboot/defaults` file defines old images purging after 3 months.

## <span dir="">Testing image and files with QEMU</span>

You can run [**QEMU**](https://wiki.archlinux.org/title/QEMU "QEMU") tests at different stages of ISO creation:

### **<span dir="">kernel and initramdisk testing</span>**

```plaintext
$ qemu-system-x86_64 -kernel yourkernel -initrd yourinitramdisk \
-append "rootfstype=ramfs" --enable-kvm -usb -usbdevice tablet
```

### **<span dir="">BIOS MBR mode</span>**

```plaintext
$ qemu-system-x86_64 -drive file=yourisofile,if=virtio,format=raw \
-usb -usbdevice tablet --enable-kvm -boot d
```

### **<span dir="">MBR mode RISC-V 64bit</span>**

```plaintext
$ qemu-system-riscv64 -M virt -kernel /usr/share/archboot/u-boot/qemu-riscv64_smode/uboot.elf \
-device virtio-gpu-pci -device virtio-net-device,netdev=eth0 \
-netdev user,id=eth0,hostfwd=tcp::2222-:22 \
-device nec-usb-xhci -device usb-tablet -device usb-kbd \
-object rng-random,filename=/dev/urandom,id=rng -device virtio-rng-device,rng=rng \
-drive file=<yourimage>,if=virtio,format=raw -m <yourmemory>
```
* Use **ssh root@localhost -p 2222** to connect to machine from your running host.

### **<span dir="">UEFI GPT mode</span>**

#### **<span dir="">64bit UEFI / 64bit running system</span>**

```plaintext
$ qemu-system-x86_64 -drive file=yourisofile,if=virtio,format=raw \
-usb -usbdevice tablet --enable-kvm -boot d \
--bios /usr/share/edk2-ovmf/x64/OVMF.fd
```

#### **<span dir="">32bit UEFI / 64bit running system</span>**

```plaintext
$ qemu-system-x86_64 -drive file=yourisofile,if=virtio,format=raw \
-usb -usbdevice tablet --enable-kvm -boot d \
--bios /usr/share/edk2-ovmf/ia32/OVMF.fd
```

### **<span dir="">UEFI GPT Secure Boot</span>**

* Copy `OVMF_VARS.secboot.fd` to a place the user has access to it.
* The file already includes a basic set of keys from fedora ovmf package.

```plaintext
# cp /usr/share/archboot/ovmf/OVMF_VARS.secboot.fd directory
```

* Replace the bios option, with the following additional commands:

#### **<span dir="">64bit UEFI / 64bit running system</span>**

```plaintext
-drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/x64/OVMF_CODE.secboot.fd \
-drive if=pflash,format=raw,file=./OVMF_VARS.secboot.fd \
-global driver=cfi.pflash01,property=secure,value=on -machine q35,smm=on,accel=kvm \
-global ICH9-LPC.disable_s3=1
```

#### **<span dir="">32bit UEFI / 64bit running system</span>**

```plaintext
-drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/ia32/OVMF_CODE.secboot.fd \
-drive if=pflash,format=raw,file=./OVMF_VARS.secboot.fd \
-global driver=cfi.pflash01,property=secure,value=on \
-machine q35,smm=on,accel=kvm -global ICH9-LPC.disable_s3=1
```

#### **<span dir="">64bit UEFI / 64bit running system AARCH64</span>**

* [**Install**](https://wiki.archlinux.org/title/Install "Install") the [**<span dir="">edk2-armvirt</span>**](https://archlinux.org/packages/?name=edk2-armvirt) package.
* serial console only:

```plaintext
-bios /usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd -machine virt \
-cpu cortex-a57 -nographic
```

* virtio vga device with keyboard and mouse

```plaintext
-bios /usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd -machine virt \
-cpu cortex-a57 -device virtio-gpu-pci -device nec-usb-xhci \
-device usb-tablet -device usb-kbd
```

* ramfb vga device with keyboard and mouse

```plaintext
-bios /usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd -machine virt \
-cpu cortex-a57 -device ramfb -device nec-usb-xhci \
-device usb-tablet -device usb-kbd
```

### **<span dir="">Additional qemu parameters</span>**

* You can test how much RAM is needed to bootup, eg. `-m 1024` for 1GB RAM usage.

```plaintext
-m memory
```

* [**KVM**](https://wiki.archlinux.org/title/KVM "KVM") virtio network for tap0:

```plaintext
-device virtio-net-device,netdev=eth0 -netdev tap,id=eth0,ifname=tap0,script=no,downscript=no
```

* [**KVM**](https://wiki.archlinux.org/title/KVM "KVM") virtio harddisk:

```plaintext
-drive file=yourimagefile,if=virtio,format=raw
```

* normal harddisk:

```plaintext
-hda yourimagefile
```

* virtio graphic card

```plaintext
-vga virtio
```

* serial console only

```plaintext
-vga none
```

## <span dir="">Arch Linux Wiki</span>

* [**Installation Guide**](https://wiki.archlinux.org/title/Installation_Guide "Installation Guide")
* [**Improving performance**](https://wiki.archlinux.org/title/Improving_performance "Improving performance")
* [**Dual boot**](https://wiki.archlinux.org/title/Dual_boot "Dual boot")
* [**Secure Boot**](https://wiki.archlinux.org/title/Secure_Boot "Secure Boot")
* [**Serial console**](https://wiki.archlinux.org/title/Serial_console "Serial console")
* [**Parallels Desktop**](https://wiki.archlinux.org/title/Parallels_Desktop "Parallels Desktop")
* [**QEMU**](https://wiki.archlinux.org/title/QEMU "QEMU")
* [**VirtualBox**](https://wiki.archlinux.org/title/VirtualBox "VirtualBox")
* [**VMware**](https://wiki.archlinux.org/title/VMware "VMware")
* [**Gnome**](https://wiki.archlinux.org/title/Gnome "Gnome")
* [**KDE/Plasma**](https://wiki.archlinux.org/title/KDE "KDE/Plasma")
* [**Xfce**](https://wiki.archlinux.org/title/Xfce "Xfce")
* [**VNC**](https://wiki.archlinux.org/title/VNC "VNC")
* [**Wayland**](https://wiki.archlinux.org/title/Wayland "Wayland")

## <span dir="">Quick links Archboot</span>

* [**Blog**](https://www.reddit.com/r/archboot)
* [**Project page**](https://gitlab.archlinux.org/tpowa/archboot)
* [**Download**](https://pkgbuild.com/\~tpowa/archboot/iso)
* [**Screenshots**](https://pkgbuild.com/\~tpowa/archboot/web)
* [**Build sources**](https://pkgbuild.com/\~tpowa/archboot/src)
* [**Repository**](https://gitlab.archlinux.org/tpowa/archboot-repository)

## <span dir="">Quick links videos</span>

* [**Parallels Macbook M1**](https://www.youtube.com/watch?v=xo_PlJHloqk)
* [**Running local image**](https://www.youtube.com/watch?v=mb3ykTklnWU)

## <span dir="">References</span>
* [**Qemu display devices**](https://www.kraxel.org/blog/2019/09/display-devices-in-qemu/)
* [**Qemu on RISC-V**](https://colatkinson.site/linux/riscv/2021/01/27/riscv-qemu/)
