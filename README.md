# Ubuntu ZFS on Root Installer

A user-friendly installer script with **Debian-style TUI interface** for installing Ubuntu Desktop or Server on ZFS root filesystem. Features ZFSBootMenu bootloader with optional rEFInd support, native ZFS encryption, and professional guided installation.

## Why Use This Installer?

- **Easy ZFS Setup**: No complex manual commands - just run the installer
- **Modern Boot Management**: Uses ZFSBootMenu for reliable ZFS booting
- **Enterprise Features**: Native ZFS encryption, snapshots, and compression
- **Ubuntu Compatibility**: Works with Ubuntu 22.04 LTS, 24.04 LTS, and 25.04+
- **Safe Installation**: Multiple confirmation prompts and preflight checks
- **Professional Interface**: Clean dialog-based installer similar to Debian

## Key Features

- **Guided TUI Interface**: Step-by-step installation with clear options
- **UEFI + ZFSBootMenu**: Modern UEFI boot with ZFS snapshot support  
- **Smart ZFS Layout**: Optimized datasets for `/`, `/home`, `/var`, `/tmp`, `/srv`
- **Optional Encryption**: Native ZFS encryption with passphrase
- **Automatic Setup**: Handles partitioning, bootloader, and system configuration
- **Preflight Validation**: Checks system requirements before installation
- **Ubuntu Security Model**: Uses sudo instead of root login (Ubuntu default)

## Requirements

- **Live Media**: Ubuntu 22.04 LTS, 24.04 LTS, or 25.04+ live USB/DVD
- **System**: UEFI firmware (BIOS/Legacy not supported)
- **Memory**: 8 GB RAM minimum for smooth installation
- **Storage**: 20+ GB target disk (will be completely erased)
- **Network**: Internet connection for package downloads

## Installation Steps

### 1. Boot Ubuntu Live Media
Boot your system from Ubuntu live USB/DVD in **UEFI mode** (not Legacy/BIOS).

### 2. Download and Run Installer
```bash
# Download the installer
wget https://raw.githubusercontent.com/Anonymo/ubuntu-zfs-root/main/ubuntu-zfs-root.sh

# Make it executable
chmod +x ubuntu-zfs-root.sh

# Run the installer (requires root privileges)
sudo ./ubuntu-zfs-root.sh
```

### 3. Follow the TUI Interface
The installer will guide you through these steps:

1. **Edit Configuration**
   - Set hostname, username, locale, and timezone
   - Choose Desktop or Server installation

2. **Select Installation Disk**
   - Choose target disk (⚠️ **WARNING**: Will be completely erased!)
   - Multiple confirmations for removable devices

3. **Set User Password**  
   - Create your user account password
   - Optionally set ZFS encryption passphrase

4. **Configure Installation Options**
   - ✅ **ZFS Encryption** (recommended for security)
   - ✅ **HWE Kernel** (latest drivers for LTS releases)
   - **Minimal Install** (smaller package set)
   - **Passwordless Sudo** (convenience vs security trade-off)
   - **RTL8821CE WiFi Drivers** (if needed)
   - **rEFInd Bootloader** (optional, ZFSBootMenu works standalone)

5. **Start Installation**
   - Review final configuration
   - Begin automatic installation process

## Installation Process

The installer automatically performs these steps:

1. **System Validation**: Checks for root privileges, required tools, UEFI firmware, and network connectivity
2. **Disk Preparation**: Creates GPT partition table with EFI system, encrypted swap, and ZFS partitions  
3. **ZFS Pool Creation**: Sets up `rpool` with optimized datasets and optional native encryption
4. **Ubuntu Installation**: Downloads and installs Ubuntu base system via debootstrap
5. **Kernel & Packages**: Installs appropriate kernel (HWE for LTS) and Desktop/Server packages
6. **Boot Configuration**: Installs ZFSBootMenu and creates UEFI boot entries
7. **System Setup**: Configures user account, networking, locale, timezone, and services
8. **Finalization**: Generates initramfs, enables ZFS services, and cleans up

**Installation Time**: Typically 15-45 minutes depending on internet speed and selected packages.

## Ubuntu Version Support

| Version | Support | Kernel Options | ZFS Compatibility |
|---------|---------|----------------|-------------------|
| **24.04 LTS (Noble)** | ✅ Full | Standard + HWE | OpenZFS 2.2+ defaults |
| **22.04 LTS (Jammy)** | ✅ Full | Standard + HWE | OpenZFS 2.1 compatibility mode |  
| **25.04 (Plucky)** | ✅ Full | Standard kernel | OpenZFS 2.2+ defaults |
| **Future Releases** | ✅ Compatible | Standard kernel | OpenZFS 2.2+ defaults |

## Important Warnings

⚠️ **DATA LOSS WARNING**: This installer will **completely erase** the selected disk. Ensure you have backups of important data.

⚠️ **UEFI REQUIRED**: BIOS/Legacy boot is not supported. You must boot the Ubuntu live media in UEFI mode.

⚠️ **HIBERNATION**: ZFS encrypted swap uses volatile keys and disables hibernation. If you need hibernation, consider zram/zswap alternatives.

⚠️ **NETWORK DEPENDENCY**: The installer downloads packages and ZFSBootMenu components from the internet during installation.

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
