#!/bin/bash

# Ensure the script run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root!"
    exit 1
fi

# 2. Load the configuration file
CONFIG_FILE="gentoo.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found in the current directory."
    exit 1
fi

source "$CONFIG_FILE"

function validate_block_device() {
    local device="$1"
    if [[ ! -b "$device" ]]; then
        echo "Error: $device is not a valid block device."
        exit 1
    fi
}

function validate_variable() {
    local var_name="$1"
    local var_value="${!1}" # Indirect expansion to get the value of the variable name
    if [[ -z "$var_value" ]]; then
        echo "Error: Variable $var_name is not set in $CONFIG_FILE."
        exit 1
    fi
}

function verify_partitions() {
    echo "========================================================"
    echo "             PARTITION VERIFICATION STEP                "
    echo "========================================================"
    echo ""
    echo "Please review the partition layout below before formatting."
    echo ""
    
    # 1. Show a clean tree view of the disks
    echo "--- Visual Layout (lsblk) ---"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL $EFI_DISK $ROOT_DISK
    echo ""
    
    # 2. Show detailed partition table for EFI disk
    echo "--- Detailed Info for EFI Disk ($EFI_DISK) ---"
    parted "$EFI_DISK" print
    echo ""
    
    # 3. Show detailed partition table for Root/Swap disk
    echo "--- Detailed Info for Root/Swap Disk ($ROOT_DISK) ---"
    parted "$ROOT_DISK" print
    echo ""
    
    echo "========================================================"
    echo "Expected Layout:"
    echo "  $EFI_DISK -> 1 partition (ESP, fat32, size: $EFI_SIZE)"
    echo "  $ROOT_DISK -> 2 partitions (1: linux-swap size: $SWAP_SIZE, 2: btrfs size: rest of disk)"
    echo "========================================================"
    echo ""
    
    # Prompt for confirmation. Using 'yes' instead of 'y' prevents accidental Enter presses.
    read -p "Does the layout match your expectations? Type 'yes' to continue: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborting script. No filesystems were created."
        exit 1
    fi
    
    echo "Verification passed. Proceeding to filesystem creation..."
}

echo "Validating configuration..."
validate_variable "EFI_DISK"
validate_variable "ROOT_DISK"
validate_variable "EFI_PART"
validate_variable "ROOT_PART"
validate_variable "SWAP_PART"

validate_block_device "$EFI_DISK"
validate_block_device "$ROOT_DISK"

echo "Configuration loaded successfully."
echo "EFI Disk: $EFI_DISK | Root Disk: $ROOT_DISK"
echo "Swap Size: $SWAP_SIZE | Hostname: $HOSTNAME"

function setup_disk() {
    echo "Starting disk setup"

    read -r -p "You are about to format the disk $EFI_DISK and $ROOT_DISK Are you sure? (y/n) " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi

    wipefs -af "$EFI_DISK"
    wipefs -af "$ROOT_DISK"

    parted -s "$EFI_DISK" mklabel gpt
    parted -s "$EFI_DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
    parted -s "$EFI_DISK" set 1 esp on

    parted -s "$ROOT_DISK" mklabel gpt
    parted -s "$ROOT_DISK" mkpart primary linux-swap 1MiB "$SWAP_SIZE"
    parted -s "$ROOT_DISK" mkpart primary btrfs "$SWAP_SIZE" 100%

    echo "Partitioning Disk is done"
    verify_partitions
}

function disk_format() {
    echo "Formating $EFI_PART"
    mkfs.vfat -F 32 "$EFI_PART"

    export GPG_TTY=$(tty)

    echo "Change DIR to ESP"
    mkdir -p /mnt/root
    mkdir -p /mnt/gentoo
    MOUNT_EFI="/mnt/gentoo/efi"
    mkdir -p "$MOUNT_EFI"
    mount "$EFI_PART" "$MOUNT_EFI"
    cd "$MOUNT_EFI" || { echo "Failed to change dir to $MOUNT_EFI"; exit 1;}

    echo "Creating encryption for swap"
    dd bs=8388608 count=1 if=/dev/urandom | gpg --symmetric --cipher-algo AES256 --output cryptswap_key.luks.gpg \
		|| { echo "Could not generate GPG encrypted swap keyfile"; exit 1;}
    # Use the GPG keyfile to format LUKS partition
	# Pipe decrypted key directly to cryptsetup (never stored unencrypted on disk)
	gpg --batch --yes --decrypt cryptswap_key.luks.gpg | cryptsetup luksFormat \
			--type luks2 \
			--key-file=- \
			--cipher aes-xts-plain64 \
			--key-size 512 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			--batch-mode \
			"$SWAP_PART" \
		        || { echo "Could not create luks on $SWAP_PART"; exit 1;}

	sleep 5
	
	gpg --batch --yes --decrypt "cryptswap_key.luks.gpg" | cryptsetup open --type luks2 \
			"$SWAP_PART" "$LUKS_SWAP_NAME" \
			--key-file=- \
		        ||  { echo "Could not open luks encrypted device"; exit 1;}

    echo "SWAP partition encrypted and open at /dev/mapper/$LUKS_SWAP_NAME"

    echo "Formating $SWAP_PART"
    echo "swapon"
    mkswap "/dev/mapper/$LUKS_SWAP_NAME"
    swapon "/dev/mapper/$LUKS_SWAP_NAME"

    echo "Creating encryption for root"
	dd bs=8388608 count=1 if=/dev/urandom | gpg --symmetric --cipher-algo AES256 --output cryptroot_key.luks.gpg \
		|| { echo "Could not generate GPG encrypted root keyfile"; exit 1;}

    # Use the GPG keyfile to format LUKS partition
	# Pipe decrypted key directly to cryptsetup (never stored unencrypted on disk)
	gpg --batch --yes --decrypt cryptroot_key.luks.gpg | cryptsetup luksFormat \
			--type luks2 \
			--key-file=- \
			--cipher aes-xts-plain64 \
			--key-size 512 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			--batch-mode \
			"$ROOT_PART" \
		        || { echo "Could not create luks on $ROOT_PART"; exit 1;}

	sleep 5
	
	gpg --batch --yes --decrypt cryptroot_key.luks.gpg \
		| cryptsetup open --type luks2 \
			"$ROOT_PART" "$LUKS_ROOT_NAME" \
			--key-file=- \
		        || { echo "Could not open luks encrypted device"; exit 1;}

    echo "Root partition encrypted and open at /dev/mapper/$LUKS_ROOT_NAME"

    echo "Change dir back to /"
    cd || { echo "Failed to change dir to /"; exit 1;}

    echo "Formating  $ROOT_PART"
    mkfs.btrfs -L BTROOT "/dev/mapper/$LUKS_ROOT_NAME" || { echo "Failed to create btrfs"; exit 1; }
    echo "mounting filesystem to /mnt/root"
    mount -t btrfs -o defaults,noatime,compress=zstd "/dev/mapper/$LUKS_ROOT_NAME" /mnt/root || { echo "Failed to mount btrfs /dev/mapper/$LUKS_ROOT_NAME to /mnt/root"; exit 1; }

    # Create subvolumes
    echo "creation of subvolumes"
    for sub in activeroot home etc var log tmp; do
        btrfs subvolume create "/mnt/root/$sub" || { echo "Failed to create subvolume $sub"; exit 1; }
    done

    # Creating and mounting to root
    echo "Mounting everything to /mnt/gentoo"
    mount -t btrfs -o defaults,noatime,compress=zstd,subvol=activeroot "/dev/mapper/$LUKS_ROOT_NAME" /mnt/gentoo/
    mkdir /mnt/gentoo/{home,etc,var,log,tmp,efi}
    for sub in home etc var log tmp; do
        mount -t btrfs -o defaults,noatime,compress=zstd,subvol=$sub "/dev/mapper/$LUKS_ROOT_NAME" /mnt/gentoo/$sub
    done

}