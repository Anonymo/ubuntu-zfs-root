# Ubuntu ZFS on Root Installation Script

A comprehensive bash script that provides a **Debian-installer style TUI** for installing Ubuntu Desktop with ZFS on root, ZFSBootMenu, and rEFInd bootloader. The familiar ncurses-based interface guides you through the entire installation process.

## Features

- **Debian-style TUI installer** - Familiar ncurses-based interface similar to Debian installer
- Automated ZFS on root installation for Ubuntu Desktop
- ZFSBootMenu integration for boot environments
- rEFInd bootloader support
- Native ZFS encryption support
- Automated partitioning and pool creation
- Support for both UEFI and legacy BIOS systems
- Interactive menu-driven installation process

## Prerequisites

- Ubuntu Desktop installation media
- Target system with UEFI or BIOS support
- Minimum 8GB RAM recommended
- At least 20GB available disk space

## Usage

1. Boot from Ubuntu live USB/DVD
2. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/Anonymo/ubuntu-zfs-root/main/ubuntu-zfs-root.sh
   ```
3. Make it executable:
   ```bash
   chmod +x ubuntu-zfs-root.sh
   ```
4. Run the script:
   ```bash
   sudo ./ubuntu-zfs-root.sh
   ```

## What the Script Does

1. **Disk Preparation**: Automatically partitions the selected disk with EFI, boot, and ZFS partitions
2. **ZFS Pool Creation**: Creates encrypted or unencrypted ZFS pool based on user preference
3. **Ubuntu Installation**: Installs Ubuntu Desktop with ZFS as the root filesystem
4. **Bootloader Setup**: Configures ZFSBootMenu and rEFInd for reliable booting
5. **System Configuration**: Sets up necessary ZFS datasets and system configurations

## Supported Ubuntu Versions

- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)

## Warning

This script will **completely erase** the selected disk. Make sure to backup any important data before running.

## License

This script is provided as-is without warranty. Use at your own risk.

## Contributing

Issues and pull requests are welcome at https://github.com/Anonymo/ubuntu-zfs-root