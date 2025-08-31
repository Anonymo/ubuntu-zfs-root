# Ubuntu ZFS on Root Installation Script

A comprehensive bash script that provides a **Debian‑installer style TUI** for installing Ubuntu on ZFS root with ZFSBootMenu, optionally with rEFInd chainloading. The familiar ncurses interface guides you through the entire process.

## Features

- **Debian‑style TUI**: simple, structured flow
- **UEFI + ZFSBootMenu**: primary boot method (rEFInd optional)
- **Preflight checks**: root, tools, UEFI mode, networking
- **Sensible ZFS layout**: rpool/ROOT/<id>, home, var, tmp, srv
- **Encryption**: native ZFS passphrase prompt (optional)
- **Jammy‑only compatibility**: uses OpenZFS 2.1 compatibility on 22.04, defaults on newer
- **Reliable boot**: zpool.cache copied into target initramfs
- **Mirror override**: choose archive mirror via `MIRROR_URL`
- **Optional rEFInd**: install and theme can be toggled
- **Debug mode**: `DEBUG=true` enables shell tracing

## Prerequisites

- Ubuntu Desktop live media (22.04 LTS or 24.04 LTS recommended)
- Target system with UEFI firmware (this installer targets UEFI)
- Minimum 8 GB RAM recommended
- At least 20 GB available disk space (disk is fully erased)

## Quick Start

1. Boot from Ubuntu live USB/DVD (UEFI mode)
2. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/Anonymo/ubuntu-zfs-root/main/ubuntu-zfs-root.sh
   chmod +x ubuntu-zfs-root.sh
   ```
3. (Optional) Set environment overrides, e.g.:
   ```bash
   export DEBUG=false           # set true to trace
   export INSTALL_REFIND=false  # set true to also install rEFInd
   export MIRROR_URL=           # leave empty to auto-select; or set custom mirror
   export RELEASE=noble         # noble (24.04) or jammy (22.04)
   export ID=ubuntu             # dataset under rpool/ROOT
   ```
4. Run the installer:
   ```bash
   sudo ./ubuntu-zfs-root.sh
   ```
5. In the TUI:
   - Quick Setup: hostname, user, locale, timezone
   - Select Installation Disk: pick the target disk (will be erased)
   - Set Passwords: root, user, and optional ZFS encryption passphrase
   - Installation Options: encryption, HWE kernel, minimal install, sudo policy, Wi‑Fi driver, optional rEFInd
   - Start Installation

## What the Script Does

1. Preflight: root, tools, UEFI presence, DNS check
2. Disk prep: GPT with EFI, swap, and ZFS partitions (disk wiped)
3. ZFS pool: creates `rpool` with tuned dataset layout and optional encryption
4. Bootstrap: debootstrap + dist‑upgrade to the chosen release
5. Kernel & base packages: HWE or standard, desktop/server meta as selected
6. ZFSBootMenu: downloads EFI binary and registers UEFI boot entries
7. Optional rEFInd: installs and configures theme/entries if enabled
8. System config: locale, timezone, user, sudo policy, networking
9. Initramfs: zpool.cache included and services enabled

## Supported Ubuntu Versions

- Ubuntu 24.04 LTS (Noble) – default settings
- Ubuntu 22.04 LTS (Jammy) – enables OpenZFS 2.1 compatibility

## Warning

This script will **completely erase** the selected disk. Double‑check the disk selection and ensure you have backups.

UEFI firmware is required for the default flow. BIOS/legacy is not supported in this installer.

The ZFS encrypted swap configuration uses a volatile key (urandom) and disables hibernation. Consider zram/zswap if hibernation is desired.

The ZFSBootMenu EFI binary is downloaded over HTTPS; for production, consider pinning a checksum or hosting internally.

This installer follows the ZFSBootMenu UEFI guide spirit: https://docs.zfsbootmenu.org/en/v3.0.x/guides/ubuntu/uefi.html

## Advanced Options (Environment Variables)

- `RELEASE`: `noble` (24.04), `jammy` (22.04). Defaults to `noble`.
- `ID`: root dataset name under `rpool/ROOT` (default: `ubuntu`).
- `ENCRYPTION`: `true`/`false` for native ZFS encryption.
- `HWE_KERNEL`: `true`/`false`. Falls back to `linux-generic` if HWE meta unavailable.
- `MINIMAL_INSTALL`: `true`/`false` for smaller package set.
- `PASSWORDLESS_SUDO`: `true`/`false`.
- `INSTALL_REFIND`: `true` to also install rEFInd; default `false` (ZFSBootMenu alone is sufficient).
- `MIRROR_URL`: override Ubuntu archive mirror; defaults to `archive.ubuntu.com`, auto‑fallback to `old-releases` for EOL series.
- `DEBUG`: `true` enables shell tracing.

Set before running the script, for example:

```bash
export INSTALL_REFIND=true DEBUG=true RELEASE=jammy ID=workstation
sudo ./ubuntu-zfs-root.sh
```

## License

This script is provided as-is without warranty. Use at your own risk.

## Contributing

Issues and pull requests are welcome at https://github.com/Anonymo/ubuntu-zfs-root
