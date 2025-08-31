# Ubuntu ZFS on Root Installer

A clean, dialog-based installer for Ubuntu Desktop or Server on ZFS root. It configures ZFSBootMenu (with optional rEFInd), native ZFS encryption, and a sensible dataset layout — without manual commands.

## Highlights

- Guided TUI: straightforward steps with clear prompts
- UEFI + ZFSBootMenu: reliable boot management for ZFS
- Sane ZFS layout: datasets for `/`, `/home`, `/var`, `/tmp`, `/srv`
- Optional encryption: native ZFS passphrase
- Preflight checks: validates tools, UEFI, basic networking
- Ubuntu defaults: user + sudo; root login remains locked

## Requirements

- Live media: Ubuntu 24.04 LTS or 22.04 LTS (25.04 works with standard kernel)
- Firmware: UEFI mode (Legacy/BIOS is not supported)
- Memory: 8 GB RAM recommended
- Disk: 20+ GB on the target device (it will be erased)
- Network: Internet connection for packages and ZFSBootMenu download

## Quick Start

1) Boot the Ubuntu live environment in UEFI mode
2) Download and run the installer
   ```bash
   wget https://raw.githubusercontent.com/Anonymo/ubuntu-zfs-root/main/ubuntu-zfs-root.sh
   chmod +x ubuntu-zfs-root.sh
   sudo ./ubuntu-zfs-root.sh
   ```
3) In the TUI
   - Edit Configuration: hostname, username, locale, timezone, distro type
   - Select Installation Disk: choose the target disk (it will be erased)
   - Set Passwords: user password and optional ZFS encryption passphrase
   - Installation Options: encryption, HWE on LTS, minimal install, sudo policy, driver, optional rEFInd
   - Start Installation

Environment overrides (optional):
```bash
export RELEASE=noble          # noble (24.04) or jammy (22.04)
export ID=ubuntu              # rpool/ROOT/<ID>
export INSTALL_REFIND=false   # also install rEFInd if true
export ENCRYPTION=true        # native ZFS encryption
export HWE_KERNEL=true        # HWE on LTS; standard kernel elsewhere
export MIRROR_URL=            # leave empty to auto-select default
export DEBUG=false            # true for verbose shell tracing
```

## What It Does

1. Preflight: checks root, tools, UEFI presence, DNS
2. Disk prep: GPT with EFI, swap, and ZFS partitions
3. ZFS pool: creates `rpool` with tuned datasets; optional encryption
4. Bootstrap: debootstrap + dist-upgrade to the chosen release
5. Kernel and packages: HWE for LTS; standard kernel otherwise
6. Boot: installs ZFSBootMenu and registers UEFI entries; rEFInd optional
7. System config: locale, timezone, user, sudo policy, networking
8. Initramfs: includes zpool.cache; enables ZFS services

Typical duration: 15–45 minutes depending on network and packages.

## Supported Ubuntu Versions

- 24.04 LTS (Noble): standard or HWE kernel; OpenZFS 2.2 defaults
- 22.04 LTS (Jammy): standard or HWE kernel; OpenZFS 2.1 compatibility
- 25.04 and newer: standard kernel by default

## Warnings

- Disk erase: the selected disk is wiped completely.
- UEFI only: legacy BIOS is not supported.
- Hibernation: encrypted swap uses a volatile key; hibernation is not supported.
- Network: requires internet for packages and ZFSBootMenu.

## Troubleshooting

- Where are logs?
  - Installer log: `/tmp/ubuntu-zfs-root-installer.log`
  - View live output during install: `tail -f /tmp/ubuntu-zfs-root-installer.log`

- The installer looks stuck at “Creating ZFS pool”
  - The installer now times out zpool create (default 180s). On timeout/error it logs diagnostics and aborts.
  - Causes include: udev not settled, stale ZFS labels, devices still in use, or hardware issues.
  - Fix quickly via the menu: choose “Clean/Reset Target Disk” and try again.

- How do I completely reset and start over?
  - Use the menu item “Clean/Reset Target Disk”. It unmounts, swapoff, exports/destroys rpool, clears ZFS labels, wipes the disk, and reprobes.
  - Manual reset (if needed):
    ```bash
    sudo umount -n -R /mnt || true
    sudo swapoff -a || true
    sudo zpool export rpool || true
    sudo zpool destroy -f rpool || true
    # Clear any ZFS labels on likely devices
    for d in /dev/disk/by-id/*-part1 /dev/disk/by-id/*-part2 /dev/disk/by-id/*-part3; do
      [ -b "$d" ] && sudo zpool labelclear -f "$d" || true
    done
    # Wipe and zap the disk
    sudo wipefs -a /dev/yourdisk
    sudo sgdisk --zap-all /dev/yourdisk
    sudo partprobe /dev/yourdisk
    sudo udevadm settle --timeout 30
    ```

- I don’t see a cursor when editing
  - The “Edit Configuration” menu uses input boxes with a visible cursor. If it still looks odd, ensure your terminal supports cursor visibility in ncurses apps.

- It says UEFI not detected
  - Reboot and ensure the live USB is booted in UEFI mode (not Legacy/CSM). The installer targets UEFI only.

- Network errors
  - Ensure DNS works: `getent hosts archive.ubuntu.com`
  - You can override the mirror with `MIRROR_URL`.

## License

This script is provided as-is without warranty. Use at your own risk.

## Contributing

Issues and pull requests are welcome at https://github.com/Anonymo/ubuntu-zfs-root
