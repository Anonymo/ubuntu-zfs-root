#!/bin/bash
#
# ZFS on Root Ubuntu Installation Script
# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Enable shell tracing when DEBUG=true
if [[ ${DEBUG:-false} == "true" ]]; then
  set -x
fi

# Cleanup trap to ensure proper unmounting on failure
cleanup_on_error() {
  echo "Installation failed! Cleaning up..."
  umount -n -R "${MOUNTPOINT}" >/dev/null 2>&1 || true
  zpool export "${POOLNAME}" >/dev/null 2>&1 || true
}
trap cleanup_on_error ERR INT TERM

# Default configuration values - All configurable via professional interface
export DISTRO="desktop"           # Installation type (desktop/server)
export RELEASE="noble"            # Ubuntu release (noble, mantic, jammy) 
# Default disk: require explicit selection via the TUI
export DISK=""                    # Will be set by setup_disk_variables()

# Release-specific version mappings
get_release_version() {
  case "$RELEASE" in
    "noble") echo "24.04" ;;
    "mantic") echo "23.10" ;;
    "jammy") echo "22.04" ;;
    *) echo "24.04" ;;  # Default fallback
  esac
}
export ENCRYPTION="true"          # ZFS encryption (recommended)
export HWE_KERNEL="true"          # HWE kernel for latest hardware
export MINIMAL_INSTALL="false"    # Full installation by default
export PASSWORDLESS_SUDO="false"  # Secure sudo (password required)
export HOSTNAME="ubuntu-zfs"      # Default hostname
export USERNAME="ubuntu"          # Default username
export MOUNTPOINT="/mnt"          # Installation mount point
export LOCALE="en_US.UTF-8"       # System locale
export TIMEZONE="America/Chicago" # System timezone
export RTL8821CE="false"          # RTL8821CE drivers (only if needed)
export INSTALL_REFIND="false"      # Install rEFInd bootloader (optional)
export ID="ubuntu"                 # Root dataset name under rpool/ROOT

# Ubuntu archive mirror (override to use a local or regional mirror)
export MIRROR_URL="http://archive.ubuntu.com/ubuntu"

# Logging and timeouts
export LOGFILE="/tmp/ubuntu-zfs-root-installer.log"
export TIMEOUT_UDEV=30            # seconds for udevadm settle
export TIMEOUT_POOL_CREATE=180    # seconds for zpool create

log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOGFILE"; }
run_with_timeout() { local secs="$1"; shift; log "+ $*"; timeout --kill-after=10s "${secs}" "$@" | tee -a "$LOGFILE"; }
run_quiet() { log "+ $*"; "$@" | tee -a "$LOGFILE"; }

collect_diagnostics() {
  log "Collecting diagnostics..."
  lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,MOUNTPOINT | tee -a "$LOGFILE"
  (command -v zpool >/dev/null 2>&1 && zpool status -v || true) | tee -a "$LOGFILE"
  (dmesg | tail -n 200) | tee -a "$LOGFILE"
}

# Choose a mirror for the selected release if not overridden
set_default_mirror() {
  # If user overrides MIRROR_URL, keep it
  if [[ -n "${MIRROR_URL:-}" && "${MIRROR_URL}" != "http://archive.ubuntu.com/ubuntu" ]]; then
    return
  fi
  case "${RELEASE}" in
    mantic|*old*)
      MIRROR_URL="http://old-releases.ubuntu.com/ubuntu/"
      ;;
    *)
      MIRROR_URL="http://archive.ubuntu.com/ubuntu/"
      ;;
  esac
  export MIRROR_URL
}

# System settings
REBOOT="false"                    # Manual reboot (safer)
DEBUG="false"                     # Debug output
POOLNAME="rpool"                  # ZFS pool name

# Configuration menu functions
# Dialog-based TUI interface (Debian-style)
dialog_quick_setup() {
  # Welcome screen
  dialog --title "Ubuntu ZFS Root Installer" --msgbox \
    "Welcome to the Ubuntu ZFS Root Installer!\n\nThis installer will set up Ubuntu with ZFS root filesystem, optional encryption, ZFSBootMenu, and rEFInd bootloader.\n\nPress OK to edit the default configuration." 12 60

  # System configuration form
  exec 3>&1
  values=$(dialog --ok-label "Continue" --title "System Configuration" --form \
    "Configure your new Ubuntu system:" 15 60 8 \
    "Hostname:"     1 1 "$HOSTNAME"  1 15 25 0 \
    "Username:"     2 1 "$USERNAME"  2 15 25 0 \
    "Locale:"       3 1 "$LOCALE"    3 15 25 0 \
    "Timezone:"     4 1 "$TIMEZONE"  4 15 25 0 \
    2>&1 1>&3)
  exec 3>&-
  
  # Parse form values
  if [ $? = 0 ]; then
    HOSTNAME=$(echo "$values" | sed -n 1p)
    USERNAME=$(echo "$values" | sed -n 2p)  
    LOCALE=$(echo "$values" | sed -n 3p)
    TIMEZONE=$(echo "$values" | sed -n 4p)
  else
    return 1
  fi

  # Distribution type
  dialog --title "Distribution Type" --radiolist \
    "Select the type of Ubuntu installation:" 12 60 2 \
    "desktop" "Desktop (Full GUI Environment)" on \
    "server" "Server (Command Line Only)" off \
    2>tempfile
  
  if [ $? = 0 ]; then
    DISTRO=$(cat tempfile)
    rm -f tempfile
  else
    return 1
  fi

  # Installation options
  dialog --title "Installation Options" --separate-output --checklist \
    "Select installation options:" 16 60 6 \
    "encryption" "Enable ZFS Encryption (Recommended)" on \
    "hwe" "Hardware Enablement Kernel (Latest drivers)" on \
    "minimal" "Minimal Installation (Less packages)" off \
    "passwordless" "Passwordless Sudo (Less secure)" off \
    "rtl8821ce" "RTL8821CE WiFi Drivers" off \
    "refind" "Install rEFInd (optional, ZBM works alone)" off \
    2>tempfile
  
  if [ $? = 0 ]; then
    choices=$(cat tempfile)
    rm -f tempfile
    
    # Set variables based on selections
    ENCRYPTION="false"
    HWE_KERNEL="false" 
    MINIMAL_INSTALL="false"
    PASSWORDLESS_SUDO="false"
    RTL8821CE="false"
    INSTALL_REFIND="false"
    
    for choice in $choices; do
      case $choice in
        "encryption") ENCRYPTION="true";;
        "hwe") HWE_KERNEL="true";;
        "minimal") MINIMAL_INSTALL="true";;
        "passwordless") PASSWORDLESS_SUDO="true";;
        "rtl8821ce") RTL8821CE="true";;
        "refind") INSTALL_REFIND="true";;
      esac
    done
  else
    return 1
  fi

  # Configuration summary
  dialog --title "Configuration Summary" --yesno \
    "Please review your configuration:\n\n\
Hostname: $HOSTNAME\n\
Username: $USERNAME\n\
Distribution: $DISTRO\n\
Encryption: $([ "$ENCRYPTION" = "true" ] && echo "Enabled" || echo "Disabled")\n\
HWE Kernel: $([ "$HWE_KERNEL" = "true" ] && echo "Yes" || echo "No")\n\
Minimal Install: $([ "$MINIMAL_INSTALL" = "true" ] && echo "Yes" || echo "No")\n\
Locale: $LOCALE\n\
Timezone: $TIMEZONE\n\n\
Is this configuration correct?" 18 60

  return $?
}

# Dialog-based disk selection
dialog_select_disk() {
  # Get available disks
  local disk_list=""
  local disks_info=""
  
  # Build disk list for dialog
  while read -r line; do
    disk=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $3}')
    model=$(echo "$line" | awk '{print $4}' | xargs)
    mountpoint=$(echo "$line" | awk '{print $5}')
    
    # Skip if less than 20GB
    size_gb=$(echo "$size" | sed 's/G$//' | cut -d'.' -f1)
    if [[ $size_gb -lt 20 ]]; then
      continue
    fi
    
    # Check if removable (likely USB/installation media)
    removable=$(cat "/sys/block/$disk/removable" 2>/dev/null || echo "0")
    
    # Determine status
    if [[ -n "$mountpoint" && "$mountpoint" != "-" ]]; then
      status="MOUNTED"
      disk_list="$disk_list $disk \"$size - $model - [MOUNTED] $status\" off"
    elif [[ "$removable" == "1" ]]; then
      status="USB/Removable"
      disk_list="$disk_list $disk \"$size - $model - [USB] $status\" off"
    else
      status="Available"
      disk_list="$disk_list $disk \"$size - $model - [AVAILABLE] $status\" off"
      disks_info="$disks_info\n$disk: $size $model ($status)"
    fi
  done < <(lsblk -d -o NAME,TYPE,SIZE,MODEL,MOUNTPOINT | grep disk)
  
  if [[ -z "$disk_list" ]]; then
    dialog --title "Error" --msgbox "No suitable disks found (minimum 20GB required)." 8 50
    return 1
  fi

  # Show disk selection
  eval "dialog --title \"Select Installation Disk\" --radiolist \
    \"WARNING: Selected disk will be COMPLETELY ERASED!\\n\\nAvailable disks:\" \
    15 80 10 $disk_list" 2>tempfile
    
  if [ $? = 0 ]; then
    local selected_disk=$(cat tempfile)
    rm -f tempfile
    
    # Setup disk variables with the selected disk
    if ! setup_disk_variables "$selected_disk"; then
      dialog --title "Error" --msgbox "Failed to setup disk variables for $selected_disk" 8 50
      return 1
    fi
    
    # DISK is already set by setup_disk_variables to the full device path
    # (e.g. /dev/sda). Do not overwrite it with the short name here.
    
    # Extra confirmation for removable devices
    removable=$(cat "/sys/block/${selected_disk}/removable" 2>/dev/null || echo "0")
    if [[ "$removable" == "1" ]]; then
      dialog --title "REMOVABLE DEVICE WARNING" --defaultno --yesno \
        "You selected: /dev/${selected_disk} (Removable Device)\n\n\
This appears to be a USB drive or removable device.\n\
This might be your installation media!\n\n\
Are you sure this is NOT your Ubuntu Live USB?\n\n\
Continue only if you're certain this is the target disk." 14 65
      
      if [ $? != 0 ]; then
        return 1
      fi
    fi
    
    # Final confirmation
    dialog --title "FINAL WARNING" --defaultno --yesno \
      "You selected: /dev/${selected_disk}\n\n\
ALL DATA ON THIS DISK WILL BE PERMANENTLY DESTROYED!\n\n\
This action cannot be undone.\n\n\
Are you absolutely sure you want to continue?" 12 60
    
    return $?
  else
    rm -f tempfile
    return 1
  fi
}

# Dialog-based password collection
dialog_collect_passwords() {
  # User password
  exec 3>&1
  USER_PASSWORD=$(dialog --title "Set User Password" --insecure --passwordbox \
    "Enter password for $USERNAME:" 10 60 2>&1 1>&3)
  exec 3>&-

  if [ $? != 0 ] || [ -z "$USER_PASSWORD" ]; then
    return 1
  fi

  # Encryption passphrase (if encryption enabled)
  if [ "$ENCRYPTION" = "true" ]; then
    exec 3>&1
    ZFS_PASSPHRASE=$(dialog --title "Set Encryption Passphrase" --insecure --passwordbox \
      "Enter passphrase for ZFS encryption:" 10 60 2>&1 1>&3)
    exec 3>&-

    if [ $? != 0 ] || [ -z "$ZFS_PASSPHRASE" ]; then
      return 1
    fi
  fi

  return 0
}

# Dialog-based main menu
dialog_main_menu() {
  while true; do
    exec 3>&1
    selection=$(dialog --clear --title "Ubuntu ZFS Root Installer" --menu \
      "Professional Ubuntu installation with ZFS root filesystem\n\
Choose an option:" 15 60 7 \
      "1" "Edit Configuration" \
      "2" "Select Installation Disk" \
      "3" "Set Passwords" \
      "4" "Review Configuration" \
      "5" "Start Installation" \
      "6" "Clean/Reset Target Disk" \
      "7" "Exit" 2>&1 1>&3)
    exec 3>&-
    
    case $selection in
      1)
        if dialog_quick_setup; then
          dialog --title "Success" --msgbox "Configuration completed successfully!" 6 40
        fi
        ;;
      2)
        if dialog_select_disk; then
          dialog --title "Success" --msgbox "Installation disk selected: /dev/$DISK" 6 40
        fi
        ;;
      3)
        if dialog_collect_passwords; then
          dialog --title "Success" --msgbox "Passwords set successfully!" 6 40
        fi
        ;;
      4)
        dialog --title "Current Configuration" --msgbox \
          "System Configuration:\n\
Hostname: ${HOSTNAME:-Not Set}\n\
Username: ${USERNAME:-Not Set}\n\
Distribution: ${DISTRO:-Not Set}\n\
Encryption: $([ "$ENCRYPTION" = "true" ] && echo "Enabled" || echo "Disabled")\n\
HWE Kernel: $([ "$HWE_KERNEL" = "true" ] && echo "Yes" || echo "No")\n\
Installation Disk: ${DISK:-Not Selected}\n\
User Password: $([ -n "$USER_PASSWORD" ] && echo "Set" || echo "Not Set")" 14 60
        ;;
      5)
        # Validate configuration
        if [[ -z "$DISK" ]]; then
          dialog --title "Error" --msgbox "Please select an installation disk first." 6 40
          continue
        fi
        if [[ -z "${USER_PASSWORD:-}" ]]; then
          dialog --title "Error" --msgbox "Please set the user password first." 6 50
          continue
        fi
        
        # Final confirmation and start installation
        if dialog --title "Start Installation" --yesno \
          "Ready to install Ubuntu with ZFS root filesystem.\n\n\
This will take 15-45 minutes depending on internet speed.\n\n\
Start installation now?" 10 60; then
          clear
          run_installation_with_progress
          exit 0
        fi
        ;;
      6)
        # Clean/reset target disk
        force_reset_disk
        ;;
      7)
        if dialog --title "Exit" --yesno "Are you sure you want to exit?" 6 40; then
          exit 0
        fi
        ;;
      *)
        exit 0
        ;;
    esac
  done
}

# Progress display for dialog interface
show_dialog_progress() {
  local step="$1"
  local total="$2"  
  local message="$3"
  local percent=$(( (step * 100) / total ))
  
  echo "XXX"
  echo "$percent"
  echo "$message"
  echo "XXX"
}

# Installation progress wrapper for dialog
run_installation_with_progress() {
  # Create named pipe for progress communication
  local progress_pipe
  progress_pipe=$(mktemp -u)
  mkfifo "$progress_pipe"
  
  # Start dialog gauge in background
  dialog --title "Installing Ubuntu with ZFS" --gauge "Preparing installation..." 10 60 0 < "$progress_pipe" &
  local dialog_pid=$!
  
  # Execute installation steps with proper error handling
  {
    echo "XXX"
    echo "10"
    echo "Initializing system and installing dependencies..."
    echo "XXX"
    initialize
    
    echo "XXX"
    echo "20"  
    echo "Preparing disk and creating partitions..."
    echo "XXX"
    disk_prepare
    
    echo "XXX"
    echo "30"
    echo "Creating ZFS pool with$([ "$ENCRYPTION" = "true" ] && echo " encryption" || echo "out encryption")..."
    echo "XXX"
    zfs_pool_create
    
    echo "XXX"
    echo "40"
    echo "Installing Ubuntu base system (this may take several minutes)..."
    echo "XXX"
    ubuntu_debootstrap
    
    echo "XXX"
    echo "50"
    echo "Configuring swap partition..."
    echo "XXX"
    create_swap
    
    echo "XXX"
    echo "60"
    echo "Installing ZFSBootMenu..."
    echo "XXX"
    ZBM_install
    
    echo "XXX"
    echo "70"
    echo "Setting up EFI boot partition..."
    echo "XXX"
    EFI_install
    
    if [[ ${INSTALL_REFIND} =~ "true" ]]; then
      echo "XXX"
      echo "80"
      echo "Installing and configuring rEFInd bootloader..."
      echo "XXX"
      rEFInd_install
    fi
    
    echo "XXX"
    echo "90"
    echo "Configuring system settings and creating user..."
    echo "XXX"
    groups_and_networks
    create_user
    install_ubuntu
    uncompress_logs
    
    if [[ ${RTL8821CE} =~ "true" ]]; then
      echo "XXX"
      echo "95"
      echo "Installing RTL8821CE WiFi drivers..."
      echo "XXX"
      rtl8821ce_install
    fi
    
    echo "XXX"
    echo "100"
    echo "Installation completed successfully!"
    echo "XXX"
    disable_root_login
    show_system_version
    cleanup
    
  } > "$progress_pipe" 2>/dev/null
  
  # Wait for dialog to finish and clean up
  wait "$dialog_pid"
  rm -f "$progress_pipe"
  
  # Show completion
  dialog --title "Installation Complete" --msgbox \
    "Ubuntu with ZFS root filesystem has been successfully installed.\n\n\
ZFS pool created with$([ "$ENCRYPTION" = "true" ] && echo " encryption" || echo "out encryption")\n\
ZFSBootMenu$([ "${INSTALL_REFIND}" = "true" ] && echo " and rEFInd") boot entries configured\n\
System configured and ready to boot\n\n\
You can now reboot and use your new ZFS-powered Ubuntu system." 14 70
  
  # Ask about reboot
  if dialog --title "Reboot Now?" --yesno \
    "Installation is complete. Would you like to reboot now?\n\n\
Make sure to remove the installation media before rebooting." 10 60; then
    reboot
  fi
}

# Configure hostname
configure_hostname() {
  echo -n "Enter hostname [${HOSTNAME}]: "
  read -r new_hostname
  [[ -n "$new_hostname" ]] && HOSTNAME="$new_hostname"
}

# Configure username
configure_username() {
  echo -n "Enter username [${USERNAME}]: "
  read -r new_username
  [[ -n "$new_username" ]] && USERNAME="$new_username"
}

# Configure distribution type
configure_distribution() {
  echo "Select distribution type:"
  PS3="Choose distribution: "
  select distro_opt in "Desktop (Full GUI)" "Server (Command Line)" "Back"; do
    case $REPLY in
      1) DISTRO="desktop"; break;;
      2) DISTRO="server"; break;;
      3) break;;
    esac
  done
}

# Configure Ubuntu release
configure_release() {
  echo "Select Ubuntu release:"
  PS3="Choose release: "
  select release_opt in "Noble (24.04 LTS)" "Mantic (23.10)" "Jammy (22.04 LTS)" "Back"; do
    case $REPLY in
      1) RELEASE="noble"; break;;
      2) RELEASE="mantic"; break;;
      3) RELEASE="jammy"; break;;
      4) break;;
    esac
  done
}

# Configure encryption setting
configure_encryption() {
  echo "Configure disk encryption:"
  PS3="Choose encryption setting: "
  select encrypt_opt in "Enable Encryption (Recommended)" "Disable Encryption" "Back"; do
    case $REPLY in
      1) ENCRYPTION="true"; break;;
      2) ENCRYPTION="false"; break;;
      3) break;;
    esac
  done
}

# Configure HWE kernel setting
configure_hwe_kernel() {
  echo "Configure HWE kernel (Hardware Enablement):"
  PS3="Choose kernel type: "
  select hwe_opt in "HWE Kernel (Latest drivers)" "Standard Kernel (Conservative)" "Back"; do
    case $REPLY in
      1) HWE_KERNEL="true"; break;;
      2) HWE_KERNEL="false"; break;;
      3) break;;
    esac
  done
}

# Configure minimal install setting
configure_minimal_install() {
  echo "Configure installation size:"
  PS3="Choose installation type: "
  select minimal_opt in "Full Installation (More features)" "Minimal Installation (Less space)" "Back"; do
    case $REPLY in
      1) MINIMAL_INSTALL="false"; break;;
      2) MINIMAL_INSTALL="true"; break;;
      3) break;;
    esac
  done
}

# Configure sudo setting
configure_sudo() {
  echo "Configure sudo access:"
  PS3="Choose sudo setting: "
  select sudo_opt in "Passwordless Sudo (Convenient)" "Password Required (Secure)" "Back"; do
    case $REPLY in
      1) PASSWORDLESS_SUDO="true"; break;;
      2) PASSWORDLESS_SUDO="false"; break;;
      3) break;;
    esac
  done
}

# Configure locale
configure_locale() {
  echo -n "Enter locale [${LOCALE}]: "
  read -r new_locale
  [[ -n "$new_locale" ]] && LOCALE="$new_locale"
}

# Configure timezone
configure_timezone() {
  echo -n "Enter timezone [${TIMEZONE}]: "
  read -r new_timezone
  [[ -n "$new_timezone" ]] && TIMEZONE="$new_timezone"
}

# Configure RTL8821CE drivers
configure_rtl8821ce() {
  echo "Configure RTL8821CE WiFi drivers:"
  PS3="Choose driver setting: "
  select rtl_opt in "Install RTL8821CE Drivers" "Skip RTL8821CE Drivers" "Back"; do
    case $REPLY in
      1) RTL8821CE="true"; break;;
      2) RTL8821CE="false"; break;;
      3) break;;
    esac
  done
}








# Disk ID computation will happen after user selects disk
export APT="/usr/bin/apt"
export DEBIAN_FRONTEND="noninteractive"

# Function to compute disk identifiers after user selection
setup_disk_variables() {
  local selected_disk="$1"
  
  # Validate disk exists
  if [[ ! -b "/dev/${selected_disk}" ]]; then
    echo "Error: /dev/${selected_disk} is not a valid block device"
    return 1
  fi
  
  # Set primary disk variable
  DISK="/dev/${selected_disk}"
  export DISK
  
  # Try to find by-id path for reliability (follow links to verify target)
  local disk_id_path=""
  # Find all by-id links and check which one points to our exact device
  while IFS= read -r -d '' link; do
    if [[ $(readlink -f "$link") == "/dev/${selected_disk}" ]]; then
      disk_id_path="$link"
      break
    fi
  done < <(find /dev/disk/by-id -name "*${selected_disk}*" -type l -print0)
  
  if [[ -n "$disk_id_path" ]]; then
    DISKID="$disk_id_path"
  else
    # Fallback to direct device path if by-id not available
    DISKID="/dev/${selected_disk}"
  fi
  export DISKID
  
  # Compute all derived device variables
  export BOOT_DISK="${DISKID}"
  export BOOT_PART="1"
  export BOOT_DEVICE="${BOOT_DISK}-part${BOOT_PART}"

  export SWAP_DISK="${DISKID}"
  export SWAP_PART="2"
  export SWAP_DEVICE="${SWAP_DISK}-part${SWAP_PART}"

  export POOL_DISK="${DISKID}"
  export POOL_PART="3"
  export POOL_DEVICE="${POOL_DISK}-part${POOL_PART}"
  
  echo "Selected disk: ${DISK}"
  echo "Using disk ID: ${DISKID}"
  echo "Boot device: ${BOOT_DEVICE}"
  echo "Swap device: ${SWAP_DEVICE}"
  echo "Pool device: ${POOL_DEVICE}"
}

git_check() {
  if [[ ! -x /usr/bin/git ]]; then
    apt install -y git
  fi
}

# Helper function for running commands in chroot environment
run_in_chroot() {
  chroot "${MOUNTPOINT}" /bin/bash <<-EOCHROOT
$*
EOCHROOT
}

debug_me() {
  if [[ ${DEBUG} =~ "true" ]]; then
    echo "BOOT_DEVICE: ${BOOT_DEVICE:-unset}"
    echo "SWAP_DEVICE: ${SWAP_DEVICE:-unset}"
    echo "POOL_DEVICE: ${POOL_DEVICE:-unset}"
    echo "DISK: ${DISK:-unset}"
    echo "DISKID: ${DISKID:-unset}"
    if [[ -n "${DISKID:-}" && -x /usr/sbin/fdisk ]]; then
      /usr/sbin/fdisk -l "${DISKID}"
    fi
    if [[ -n "${DISKID:-}" && -x /usr/sbin/blkid ]]; then
      /usr/sbin/blkid "${DISKID}"
    fi
    read -rp "Hit enter to continue"
    if [[ -x /usr/sbin/zpool ]]; then
      /usr/sbin/zpool status "${POOLNAME}"
    fi
  fi
}

source /etc/os-release
# Note: Keep original ID from os-release, don't overwrite with RELEASE

# Device variables will be computed after disk selection in setup_disk_variables()

# debug_me called after disk selection to avoid set -u issues with unset device variables

# Swapsize autocalculated to be = Mem size
SWAPSIZE=$(free --giga | grep Mem | awk '{OFS="";print "+", $2 ,"G"}')
export SWAPSIZE

# Force cleanup/reset of target disk and related state
force_reset_disk() {
  # Ensure a disk is selected (so we know what to wipe)
  if [[ -z "${DISKID:-}" || ! -b "${DISKID:-/dev/null}" ]]; then
    if ! dialog_select_disk; then
      dialog --title "Reset Aborted" --msgbox "No disk selected." 6 40
      return 1
    fi
  fi

  if ! dialog --defaultno --yesno "This will unmount ${MOUNTPOINT}, export/destroy pools, and wipe ${DISKID}.\n\nProceed?" 10 70; then
    return 1
  fi

  log "Force resetting disk ${DISKID}"
  umount -n -R "${MOUNTPOINT}" >/dev/null 2>&1 || true
  swapoff -a >/dev/null 2>&1 || true
  zpool export "${POOLNAME}" >/dev/null 2>&1 || true
  zpool destroy -f "${POOLNAME}" >/dev/null 2>&1 || true

  # Clear ZFS labels if any
  for dev in "${POOL_DEVICE:-}" "${SWAP_DEVICE:-}" "${BOOT_DEVICE:-}" "${DISKID}"; do
    [[ -b "$dev" ]] && zpool labelclear -f "$dev" >/dev/null 2>&1 || true
  done

  wipefs -a "${DISKID}" >/dev/null 2>&1 || true
  sgdisk --zap-all "${DISKID}" >/dev/null 2>&1 || true
  partprobe "${DISKID}" >/dev/null 2>&1 || true
  udevadm settle --timeout ${TIMEOUT_UDEV} || true

  dialog --title "Reset Complete" --msgbox "Target disk has been reset. You can start the installation again." 7 60
}

# Start installation
initialize() {
  apt update
  apt install -y debootstrap gdisk zfsutils-linux vim git curl nala dialog
  zgenhostid -f
}

# Preflight checks and environment sanity
preflight() {
  # Require root
  if [[ ${EUID} -ne 0 ]]; then
    echo "This installer must be run as root"
    exit 1
  fi

  # Check basic tools
  local req_tools=(dialog sgdisk lsblk zpool zfs blkid awk sed grep)
  local missing=()
  for t in "${req_tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if ((${#missing[@]})); then
    echo "Missing tools: ${missing[*]}"
    echo "Attempting to install prerequisites..."
    apt update && apt install -y gdisk zfsutils-linux dialog || true
  fi

  # Warn if not UEFI (required by this flow)
  if [[ ! -d /sys/firmware/efi ]]; then
    dialog --title "UEFI Required" --msgbox "This guide targets UEFI systems. Please boot in UEFI mode." 8 60
  fi

  # Network check (non-fatal)
  if ! getent hosts archive.ubuntu.com >/dev/null 2>&1; then
    dialog --title "Network Warning" --msgbox "Cannot resolve archive.ubuntu.com. Ensure network is connected before installation." 8 70
  fi
}

# Disk preparation
disk_prepare() {
  debug_me

  wipefs -a "${DISKID}"
  blkdiscard -f "${DISKID}" || true  # Allow failure on non-SSD devices
  sgdisk --zap-all "${DISKID}" || { echo "Failed to wipe disk ${DISKID}"; exit 1; }
  sync
  partprobe "${DISKID}" || true
  udevadm settle --timeout ${TIMEOUT_UDEV} || true

  ## gdisk hex codes:
  ## EF02 BIOS boot partitions
  ## EF00 EFI system
  ## BE00 Solaris boot
  ## BF00 Solaris root
  ## BF01 Solaris /usr & Mac Z
  ## 8200 Linux swap
  ## 8300 Linux file system
  ## FD00 Linux RAID

  sgdisk -n "${BOOT_PART}:1m:+512m" -t "${BOOT_PART}:EF00" "${BOOT_DISK}" || { echo "Failed to create boot partition"; exit 1; }
  sgdisk -n "${SWAP_PART}:0:${SWAPSIZE}" -t "${SWAP_PART}:8200" "${SWAP_DISK}" || { echo "Failed to create swap partition"; exit 1; }
  sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:BF00" "${POOL_DISK}" || { echo "Failed to create ZFS partition"; exit 1; }
  sync
  partprobe "${DISKID}" || true
  udevadm settle --timeout ${TIMEOUT_UDEV} || true
  debug_me
}

# ZFS pool creation
zfs_pool_create() {
  # Create the zpool
  echo "------------> Create zpool <------------"
  
  # Determine compatibility property based on release (only constrain on jammy)
  local compat_args=()
  case "${RELEASE}" in
    jammy)
      compat_args+=( -o compatibility=openzfs-2.1-linux )
      ;;
    *)
      # Use defaults on newer releases (OpenZFS 2.2+)
      ;;
  esac

  if [[ ${ENCRYPTION} =~ "true" ]]; then
    echo "Setting up encrypted zpool..."
    if ! echo "${ZFS_PASSPHRASE}" | run_with_timeout ${TIMEOUT_POOL_CREATE}s zpool create -f -o ashift=12 \
      -O compression=lz4 \
      -O acltype=posixacl \
      -O xattr=sa \
      -O relatime=on \
      -O encryption=aes-256-gcm \
      -O keylocation=prompt \
      -O keyformat=passphrase \
      -o autotrim=on \
      "${compat_args[@]}" \
      -m none "${POOLNAME}" "${POOL_DEVICE}"; then
      echo "Failed to create encrypted ZFS pool (timeout or error)" | tee -a "$LOGFILE"
      collect_diagnostics
      exit 1
    fi
  else
    echo "Setting up unencrypted zpool..."
    if ! run_with_timeout ${TIMEOUT_POOL_CREATE}s zpool create -f -o ashift=12 \
      -O compression=lz4 \
      -O acltype=posixacl \
      -O xattr=sa \
      -O relatime=on \
      -o autotrim=on \
      "${compat_args[@]}" \
      -m none "${POOLNAME}" "$POOL_DEVICE"; then
      echo "Failed to create ZFS pool (timeout or error)" | tee -a "$LOGFILE"
      collect_diagnostics
      exit 1
    fi
  fi

  sync
  sleep 2

  # Create initial file systems
  zfs create -o mountpoint=none -o canmount=off "${POOLNAME}"/ROOT
  sync
  sleep 2
  zfs create -o mountpoint=/ -o canmount=noauto "${POOLNAME}"/ROOT/"${ID}"
  zfs create -o mountpoint=/home "${POOLNAME}"/home
  sync
  zpool set bootfs="${POOLNAME}"/ROOT/"${ID}" "${POOLNAME}"

  # Export, then re-import with a temporary mountpoint of "${MOUNTPOINT}"
  zpool export "${POOLNAME}"
  zpool import -N -R "${MOUNTPOINT}" "${POOLNAME}"
  
  if [[ ${ENCRYPTION} =~ "true" ]]; then
    ## Load ZFS key using pipe to avoid temporary file
    echo "${ZFS_PASSPHRASE}" | zfs load-key -L prompt "${POOLNAME}"
  fi

  zfs mount "${POOLNAME}"/ROOT/"${ID}"
  zfs mount "${POOLNAME}"/home

  # Ensure a zpool cache is generated on the installer host
  zpool set cachefile=/etc/zfs/zpool.cache "${POOLNAME}" || true

  # Create additional standard datasets with tuned properties
  zfs create -o mountpoint=/var -o atime=off "${POOLNAME}"/var
  zfs create -o mountpoint=/var/log -o recordsize=8K -o logbias=throughput -o com.sun:auto-snapshot=false "${POOLNAME}"/var/log
  zfs create -o mountpoint=/var/tmp -o com.sun:auto-snapshot=false "${POOLNAME}"/var/tmp
  zfs create -o mountpoint=/tmp -o com.sun:auto-snapshot=false "${POOLNAME}"/tmp
  zfs create -o mountpoint=/srv "${POOLNAME}"/srv

  # Update device symlinks
  udevadm trigger
  debug_me
}

# Install Ubuntu
ubuntu_debootstrap() {
  local VERSION=$(get_release_version)
  echo "------------> Installing Ubuntu ${RELEASE} (${VERSION}) <------------"
  
  # Install base system, then immediately upgrade to current point release before installing packages
  # This avoids downloading outdated packages that would be replaced
  debootstrap --include=ubuntu-keyring,ca-certificates \
    --components=main,restricted,universe,multiverse \
    --variant=minbase \
    ${RELEASE} "${MOUNTPOINT}" "${MIRROR_URL}" || { echo "Failed to install base Ubuntu system"; exit 1; }

  # Copy files into the new install
  cp /etc/hostid "${MOUNTPOINT}"/etc/hostid
  cp /etc/resolv.conf "${MOUNTPOINT}"/etc/
  mkdir "${MOUNTPOINT}"/etc/zfs
  
  if [[ ${ENCRYPTION} =~ "true" ]]; then
    # Copy key file only if it exists (pool uses passphrase prompt by default)
    if [[ -f /etc/zfs/"${POOLNAME}".key ]]; then
      cp /etc/zfs/"${POOLNAME}".key "${MOUNTPOINT}"/etc/zfs
    fi
  fi

  # Copy zpool.cache for reliable pool import in initramfs
  if [[ -f /etc/zfs/zpool.cache ]]; then
    cp /etc/zfs/zpool.cache "${MOUNTPOINT}"/etc/zfs/ || true
  fi

  # Chroot into the new OS
  mount -t proc proc "${MOUNTPOINT}"/proc
  mount -t sysfs sys "${MOUNTPOINT}"/sys
  mount -B /dev "${MOUNTPOINT}"/dev
  mount -t devpts pts "${MOUNTPOINT}"/dev/pts

  # Set a hostname
  echo "$HOSTNAME" >"${MOUNTPOINT}"/etc/hostname
  echo "127.0.1.1       $HOSTNAME" >>"${MOUNTPOINT}"/etc/hosts

  # Keep root account locked (Ubuntu default); no root password is set

  # Set up APT sources
  cat <<EOF >"${MOUNTPOINT}"/etc/apt/sources.list
# Uncomment the deb-src entries if you need source packages

deb ${MIRROR_URL} ${RELEASE} main restricted universe multiverse
# deb-src ${MIRROR_URL} ${RELEASE} main restricted universe multiverse

deb ${MIRROR_URL} ${RELEASE}-updates main restricted universe multiverse
# deb-src ${MIRROR_URL} ${RELEASE}-updates main restricted universe multiverse

deb ${MIRROR_URL} ${RELEASE}-security main restricted universe multiverse
# deb-src ${MIRROR_URL} ${RELEASE}-security main restricted universe multiverse

deb ${MIRROR_URL} ${RELEASE}-backports main restricted universe multiverse
# deb-src ${MIRROR_URL} ${RELEASE}-backports main restricted universe multiverse
EOF

  # Immediately update to current point release before installing any additional packages  
  echo "Updating base system to Ubuntu ${RELEASE} (${VERSION}) current point release..."
  run_in_chroot <<-EOCHROOT
  ${APT} update
  ${APT} dist-upgrade -y
EOCHROOT

  # Install base packages and kernel with up-to-date versions
  echo "Installing base packages with current ${RELEASE} (${VERSION}) versions..."
  run_in_chroot <<-EOCHROOT
  # Install kernel: HWE only on LTS (jammy/noble); standard kernel elsewhere
  if [[ ${HWE_KERNEL} =~ "true" ]] && [[ "${RELEASE}" == "jammy" || "${RELEASE}" == "noble" ]]; then
    echo "Installing HWE kernel for LTS release..."
    if apt-cache show linux-generic-hwe-${VERSION} >/dev/null 2>&1; then
      ${APT} install -y --no-install-recommends linux-generic-hwe-${VERSION} locales keyboard-configuration console-setup curl nala git
    else
      echo "HWE meta linux-generic-hwe-${VERSION} not available; falling back to linux-generic"
      ${APT} install -y --no-install-recommends linux-generic locales keyboard-configuration console-setup curl nala git
    fi
  else
    echo "Installing standard kernel..."
    ${APT} install -y --no-install-recommends linux-generic locales keyboard-configuration console-setup curl nala git
  fi
  
  # Install appropriate meta-package for point release tracking
  if [[ ${MINIMAL_INSTALL} =~ "true" ]]; then
    if [[ ${DISTRO} =~ "server" ]]; then
      echo "Installing ubuntu-server-minimal meta-package..."
      ${APT} install -y ubuntu-server-minimal
    else
      echo "Installing ubuntu-desktop-minimal meta-package..."
      ${APT} install -y ubuntu-desktop-minimal
    fi
  else
    # Install standard meta-package that will be upgraded to full later
    echo "Installing ubuntu-standard meta-package for proper point release tracking..."
    ${APT} install -y ubuntu-standard
  fi
EOCHROOT

  run_in_chroot <<-EOCHROOT
		##4.5 configure basic system
		locale-gen en_US.UTF-8 $LOCALE
		echo 'LANG="$LOCALE"' > /etc/default/locale

		##set timezone
		ln -fs /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
    # TODO: Make the reconfigurations below selectable by variables
		#dpkg-reconfigure locales tzdata keyboard-configuration console-setup
    dpkg-reconfigure keyboard-configuration
EOCHROOT

  # ZFS Configuration
  run_in_chroot <<-EOCHROOT
  ${APT} install -y dosfstools zfs-initramfs zfsutils-linux curl vim wget git
  systemctl enable zfs.target
  systemctl enable zfs-import-cache
  systemctl enable zfs-mount
  systemctl enable zfs-import.target
  echo "UMASK=0077" > /etc/initramfs-tools/conf.d/umask.conf
  # Ensure zpool cache exists in the target before building initramfs
  if [[ -f /etc/zfs/zpool.cache ]]; then
    echo "zpool.cache already present in target"
  else
    echo "Note: zpool.cache will be copied from installer environment"
  fi
  chmod 1777 /tmp /var/tmp || true
  update-initramfs -c -k all
EOCHROOT
}

ZBM_install() {
  # Install and configure ZFSBootMenu
  # Set ZFSBootMenu properties on datasets
  # Create a vfat filesystem first, then add fstab entry
  echo "------------> Installing ZFSBootMenu <------------"
  mkdir -p "${MOUNTPOINT}"/boot/efi

  debug_me
  run_in_chroot <<-EOCHROOT
  zfs set org.zfsbootmenu:commandline="quiet loglevel=4 splash" "${POOLNAME}"/ROOT
  zfs set org.zfsbootmenu:keysource="${POOLNAME}"/ROOT/"${ID}" "${POOLNAME}"
  mkfs.vfat -v -F32 "$BOOT_DEVICE" || { echo "Failed to format EFI boot partition"; exit 1; } # the EFI partition must be formatted as FAT32
  sync
  udevadm settle
EOCHROOT

  # Create fstab entry after formatting EFI partition using UUID
  local boot_uuid
  boot_uuid=$(blkid -s UUID -o value "$BOOT_DEVICE")
  cat <<EOF >>${MOUNTPOINT}/etc/fstab
UUID=${boot_uuid} /boot/efi vfat umask=0077,shortname=mixed 0 0
EOF

  # Install ZBM and configure EFI boot entries
  run_in_chroot <<-EOCHROOT
  mount /boot/efi
  mkdir -p /boot/efi/EFI/ZBM
  curl -o /boot/efi/EFI/ZBM/VMLINUZ.EFI -L https://get.zfsbootmenu.org/efi
  cp /boot/efi/EFI/ZBM/VMLINUZ.EFI /boot/efi/EFI/ZBM/VMLINUZ-BACKUP.EFI
  mount -t efivarfs efivarfs /sys/firmware/efi/efivars
  
  # Cleanup: unmount efivarfs before exiting chroot to prevent lingering mounts
  umount /sys/firmware/efi/efivars || true
EOCHROOT
}

# Create boot entry with efibootmgr
EFI_install() {
  echo "------------> Installing efibootmgr <------------"
  
  # Check for UEFI firmware presence
  if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "UEFI firmware not detected. This system appears to be BIOS/Legacy mode."
    echo "This script requires UEFI mode. Please boot in UEFI mode and try again."
    exit 1
  fi
  
  # efivarfs will be mounted inside the chroot for efibootmgr
  
  debug_me
  run_in_chroot <<-EOCHROOT
mount -t efivarfs efivarfs /sys/firmware/efi/efivars || true
${APT} install -y efibootmgr
efibootmgr -c -d "${DISK}" -p "${BOOT_PART}" \
  -L "ZFSBootMenu (Backup)" \
  -l '\EFI\ZBM\VMLINUZ-BACKUP.EFI'

efibootmgr -c -d "${DISK}" -p "${BOOT_PART}" \
  -L "ZFSBootMenu" \
  -l '\EFI\ZBM\VMLINUZ.EFI'

sync
sleep 1
umount /sys/firmware/efi/efivars || true
EOCHROOT

  # efivarfs was mounted inside chroot and unmounted there
}

# Install rEFInd
# Install rEFInd bootloader
install_refind_bootloader() {
  echo "Installing rEFInd bootloader..."
  run_in_chroot <<-EOCHROOT
  ${APT} install -y curl refind
  refind-install
  [[ -f /boot/refind_linux.conf ]] && rm /boot/refind_linux.conf
EOCHROOT
}

# Install rEFInd theme
install_refind_theme() {
  echo "Installing rEFInd theme..."
  
  # Use temporary directory for cleanliness
  local temp_dir
  temp_dir=$(mktemp -d) || return 1
  
  cd "$temp_dir" || return 1
  git_check
  
  # Download theme
  /usr/bin/git clone https://github.com/bobafetthotmail/refind-theme-regular.git
  
  # Clean up theme
  rm -rf refind-theme-regular/{src,.git}
  rm -f refind-theme-regular/install.sh 2>/dev/null
  
  # Remove old themes
  rm -rf "${MOUNTPOINT}"/boot/efi/EFI/refind/{regular-theme,refind-theme-regular}
  rm -rf "${MOUNTPOINT}"/boot/efi/EFI/refind/themes/{regular-theme,refind-theme-regular}
  
  # Install new theme
  mkdir -p "${MOUNTPOINT}"/boot/efi/EFI/refind/themes
  sync && sleep 2
  cp -r refind-theme-regular "${MOUNTPOINT}"/boot/efi/EFI/refind/themes/
  sync && sleep 2
  
  # Configure theme
  sed -e '/128/ s/^/#/' \
      -e '/48/ s/^/#/' \
      -e '/ 96/ s/^#//' \
      -e '/ 256/ s/^#//' \
      -e '/256-96.*dark/ s/^#//' \
      -e '/icons_dir.*256/ s/^#//' \
      refind-theme-regular/theme.conf > "${MOUNTPOINT}"/boot/efi/EFI/refind/themes/refind-theme-regular/theme.conf
  
  # Clean up temporary directory
  cd / && rm -rf "$temp_dir"
}

# Configure rEFInd bootloader
configure_refind() {
  echo "Configuring rEFInd bootloader..."
  
  cat <<EOF >>"${MOUNTPOINT}"/boot/efi/EFI/refind/refind.conf
menuentry "Ubuntu (ZBM)" {
    loader /EFI/ZBM/VMLINUZ.EFI
    icon /EFI/refind/themes/refind-theme-regular/icons/256-96/os_ubuntu.png
    options "quit loglevel=0 zbm.skip"
}

menuentry "Ubuntu (ZBM Menu)" {
    loader /EFI/ZBM/VMLINUZ.EFI
    icon /EFI/refind/themes/refind-theme-regular/icons/256-96/os_ubuntu.png
    options "quit loglevel=0 zbm.show"
}

include themes/refind-theme-regular/theme.conf
EOF
}

# Main rEFInd installation function
rEFInd_install() {
  echo "------------> Install rEFInd <-------------"
  
  install_refind_bootloader
  install_refind_theme
  configure_refind
  
  if [[ ${DEBUG} =~ "true" ]]; then
    read -rp "Finished w/ rEFInd... waiting."
  fi
}

# Setup swap partition

create_swap() {
  echo "------------> Create swap partition <------------"

  debug_me
  echo swap "${SWAP_DEVICE}" /dev/urandom \
    plain,swap,cipher=aes-xts-plain64,hash=sha256,size=512 >>"${MOUNTPOINT}"/etc/crypttab
  echo /dev/mapper/swap none swap defaults 0 0 >>"${MOUNTPOINT}"/etc/fstab
}

# Setup encrypted swap partition  
swap_setup() {
  echo "------------> Setting up encrypted swap <------------"
  create_swap
  
  # Note: mkswap will be done automatically on first boot when cryptsetup opens the device
  # The systemd-cryptsetup service handles this for swap devices defined in crypttab
  echo "Encrypted swap configured - will be formatted automatically on first boot"
}

# Create system groups and network setup
groups_and_networks() {
  echo "------------> Setup groups and networks <----------------"
  run_in_chroot <<-EOCHROOT
  cp /usr/share/systemd/tmp.mount /etc/systemd/system/
  systemctl enable tmp.mount
  addgroup --system lpadmin
  addgroup --system lxd
  addgroup --system sambashare

  # Configure network renderer based on distro type and NetworkManager availability
  if [[ "${DISTRO}" == "desktop" ]] || dpkg -l | grep -q network-manager; then
    echo "network:" >/etc/netplan/01-network-manager-all.yaml
    echo "  version: 2" >>/etc/netplan/01-network-manager-all.yaml
    echo "  renderer: NetworkManager" >>/etc/netplan/01-network-manager-all.yaml
    echo "Configured NetworkManager as network renderer for desktop system"
  else
    echo "network:" >/etc/netplan/01-netcfg.yaml
    echo "  version: 2" >>/etc/netplan/01-netcfg.yaml
    echo "  renderer: networkd" >>/etc/netplan/01-netcfg.yaml
    echo "  ethernets:" >>/etc/netplan/01-netcfg.yaml
    echo "    enp*:" >>/etc/netplan/01-netcfg.yaml
    echo "      match:" >>/etc/netplan/01-netcfg.yaml
    echo "        name: \"enp*\"" >>/etc/netplan/01-netcfg.yaml
    echo "      dhcp4: true" >>/etc/netplan/01-netcfg.yaml
    echo "    eth*:" >>/etc/netplan/01-netcfg.yaml
    echo "      match:" >>/etc/netplan/01-netcfg.yaml
    echo "        name: \"eth*\"" >>/etc/netplan/01-netcfg.yaml
    echo "      dhcp4: true" >>/etc/netplan/01-netcfg.yaml
    echo "Configured systemd-networkd as network renderer for server system"
  fi
EOCHROOT
}

# Create user
create_user() {
  run_in_chroot <<-EOCHROOT
  adduser --disabled-password --gecos "" ${USERNAME}
  cp -a /etc/skel/. /home/${USERNAME}
  chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
  usermod -a -G adm,cdrom,dip,lpadmin,lxd,plugdev,sambashare,sudo ${USERNAME}
  
  # Configure sudo based on PASSWORDLESS_SUDO setting
  if [[ ${PASSWORDLESS_SUDO} =~ "true" ]]; then
    echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/${USERNAME}
    echo "Configured passwordless sudo for ${USERNAME}"
  else
    echo "${USERNAME} ALL=(ALL) ALL" >/etc/sudoers.d/${USERNAME}
    echo "Configured password-required sudo for ${USERNAME}"
  fi
  chown root:root /etc/sudoers.d/${USERNAME}
  chmod 440 /etc/sudoers.d/${USERNAME}
  echo -e "${USERNAME}:${USER_PASSWORD}" | chpasswd
EOCHROOT
}

# Install distro bundle
install_ubuntu() {
  echo "------------> Installing ${DISTRO} bundle <------------"
  debug_me
  
  run_in_chroot <<-EOCHROOT
    # System is already at current ${RELEASE} version - just update package cache
    ${APT} update

    #TODO: Unlock more cases

    # Install distribution packages based on MINIMAL_INSTALL setting
		case "${DISTRO}" in
		server)
		  if [[ ${MINIMAL_INSTALL} =~ "true" ]]; then
		    echo "Installing minimal server packages..."
		    ${APT} install -y ubuntu-server-minimal
		  else
		    echo "Installing full server packages..."
		    ${APT} install -y ubuntu-server
		  fi
		;;
		desktop)
		  if [[ ${MINIMAL_INSTALL} =~ "true" ]]; then
		    echo "Installing minimal desktop packages..."
		    ${APT} install -y ubuntu-desktop-minimal
		  else
		    echo "Installing full desktop packages..."
		    ${APT} install -y ubuntu-desktop
		  fi
		;;
    *)
      echo "No distro selected."
    ;;
    esac
    
    # Install essential system packages for encrypted swap
    echo "Installing essential system packages..."
    ${APT} install -y cryptsetup-initramfs openssh-server
		# 	kubuntu)
		# 		##Ubuntu KDE plasma desktop install has a full GUI environment.
		# 		##Select sddm as display manager.
		# 		echo sddm shared/default-x-display-manager select sddm | debconf-set-selections
		# 		${APT} install --yes kubuntu-desktop
		# 	;;
		# 	xubuntu)
		# 		##Ubuntu xfce desktop install has a full GUI environment.
		# 		##Select lightdm as display manager.
		# 		echo lightdm shared/default-x-display-manager select lightdm | debconf-set-selections
		# 		${APT} install --yes xubuntu-desktop
		# 	;;
		# 	budgie)
		# 		##Ubuntu budgie desktop install has a full GUI environment.
		# 		##Select lightdm as display manager.
		# 		echo lightdm shared/default-x-display-manager select lightdm | debconf-set-selections
		# 	;;
		# 	MATE)
		# 		##Ubuntu MATE desktop install has a full GUI environment.
		# 		##Select lightdm as display manager.
		# 		echo lightdm shared/default-x-display-manager select lightdm | debconf-set-selections
		# 		${APT} install --yes ubuntu-mate-desktop
		# 	;;
    # esac
EOCHROOT
}

# Disable log gzipping as we already use compresion at filesystem level
uncompress_logs() {
  echo "------------> Uncompress logs <------------"
  run_in_chroot <<-EOCHROOT
  for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "${file}" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "${file}"
    fi
  done
EOCHROOT
}

# Ensure root account is locked (Ubuntu default)
disable_root_login() {
  echo "------------> Disable root login <------------"
  run_in_chroot <<-EOCHROOT
  passwd -l root || true
EOCHROOT
}

# Show final system version
show_system_version() {
  echo "------------> Final system version <------------"
  run_in_chroot <<-EOCHROOT
  echo "Installed Ubuntu version:"
  lsb_release -a
  echo ""
  echo "Kernel version:"
  uname -r 2>/dev/null || echo "Kernel not yet active (will show after reboot)"
  echo ""
  echo "Available kernel packages:"
  dpkg -l | grep linux-image | head -5
EOCHROOT
}

#Umount target and final cleanup
cleanup() {
  echo "------------> Final cleanup <------------"
  umount -n -R "${MOUNTPOINT}"
  sync
  sleep 5
  umount -n -R "${MOUNTPOINT}" >/dev/null 2>&1

  zpool export "${POOLNAME}"
}

# Download and install RTL8821CE drivers
rtl8821ce_install() {
  echo "------------> Installing RTL8821CE drivers <------------"
  run_in_chroot <<-EOCHROOT
  ${APT} install -y bc module-assistant build-essential dkms
  m-a prepare
  cd /root
  ${APT} install -y git
  /usr/bin/git clone https://github.com/tomaspinho/rtl8821ce.git
  cd rtl8821ce
  ./dkms-install.sh
  zfs set org.zfsbootmenu:commandline="quiet loglevel=4 splash pcie_aspm=off" "${POOLNAME}"/ROOT
  echo "blacklist rtw88_8821ce" >> /etc/modprobe.d/blacklist.conf
EOCHROOT
}

# Function to run installation after basic menu completion
run_basic_installation() {
  echo ""
  echo "Starting Ubuntu ZFS installation..."
  echo ""
  
  initialize
  disk_prepare
  zfs_pool_create
  ubuntu_debootstrap
  create_swap
  ZBM_install
  EFI_install
  if [[ ${INSTALL_REFIND} =~ "true" ]]; then
    rEFInd_install
  fi
  groups_and_networks
  create_user
  install_ubuntu
  uncompress_logs
  if [[ ${RTL8821CE} =~ "true" ]]; then
    rtl8821ce_install
  fi
  disable_root_login
  show_system_version
  cleanup

  echo ""
  echo "Installation completed successfully!"
  echo ""

  if [[ ${REBOOT} =~ "true" ]]; then
    reboot
  fi
}



################################################################
# MAIN Program

# Preflight: check environment and set defaults
set_default_mirror

# Check if dialog is available
if ! command -v dialog >/dev/null 2>&1; then
  echo "Error: dialog package is required for the TUI installer"
  echo "Please install it with: apt install dialog"
  exit 1
fi

preflight

# Run the TUI installer main menu
dialog_main_menu
