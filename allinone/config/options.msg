Arch Linux options and troubleshooting:
- If you have trouble with IDE drives, use the "ide-legacy" boot option
- If your system hangs during the boot process, any combinations of the
  boot options noapic acpi=off pci=routeirq nosmp may be useful.

- ARCH_INTEL_WIRELESS USAGE:
  In order to use those drivers, you have to agree to the firmware licenses
  by appending intel-wireless to boot prompt.

- ARCH_ADDONS USAGE:
  In order to load external addon packages or configs
  into the install environment, please append arch-addons to boot prompt.
  Place external addon packages in /packages directory.
  Place external configs in /config directory.

- ARCH_TIACX_WIRELESS USAGE:
  Please identify the correct file(s) for your device in /usr/share/tiacx 
  and copy them to /lib/firmware and reload your kernel module.
  See http://acx100.sourceforge.net/wiki/Firmware for details.

- For returning to start screen press F1 key.



