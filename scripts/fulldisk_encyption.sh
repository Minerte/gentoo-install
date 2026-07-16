# Helper funtions

function mkdir_or_die() {
	# shellcheck disable=SC2174
	mkdir -m "$1" -p "$2" \
		|| die "Could not create directory '$2'"
}

function die() {
	eerror "$*"
	[[ -v GENTOO_INSTALL_REPO_SCRIPT_PID && $$ -ne $GENTOO_INSTALL_REPO_SCRIPT_PID ]] \
		&& kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"
	exit 1
}

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

function download() {
    local url="$1"
    local output="$2"
    wget -q --show-progress -O "$output" "$url" || curl -fLo "$output" "$url"
}

function download_stdout() {
    local url="$1"
    wget -qO- "$url" || curl -fsSL "$url"
}


function preprocess_config() {
	check_config
}

function check_config() {
	[[ $KEYMAP =~ ^[0-9A-Za-z-]*$ ]] \
		|| die "KEYMAP contains invalid characters"

	if [[ "$STAGE3_BASENAME" != *systemd* ]]; then
		[[ "$STAGE3_BASENAME" != *systemd* ]] \
			|| die "Using OpenRC requires a non-systemd stage3 archive!"
	else
			die "Failed"
	fi

	# Check hostname per RFC1123
	local hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
	[[ $HOSTNAME =~ $hostname_regex ]] \
		|| die "'$HOSTNAME' is not a valid hostname"

	[[ -v "DISK_ID_ROOT" && -n $DISK_ID_ROOT ]] \
		|| die "You must assign DISK_ID_ROOT"
	[[ -v "DISK_ID_EFI" && -n $DISK_ID_EFI ]] \
		|| die "You must assign DISK_ID_EFI"

	[[ -v "DISK_ID_EFI" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_EFI]" ]] \
		&& die "Missing uuid for DISK_ID_EFI, have you made sure it is used?"
	[[ -v "DISK_ID_SWAP" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_SWAP]" ]] \
		&& die "Missing uuid for DISK_ID_SWAP, have you made sure it is used?"
	[[ -v "DISK_ID_ROOT" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_ROOT]" ]] \
		&& die "Missing uuid for DISK_ID_ROOT, have you made sure it is used?"

	if [[ -v "DISK_ID_EFI" ]]; then
		IS_EFI=true # Taken from main
	else
		die
	fi
}


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
    mkdir -p "$BTRFS_TEMP_MOUNT"
    mkdir -p "$ROOT_MOUNTPOINT"
    MOUNT_EFI="$ROOT_MOUNTPOINT/efi"
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
    mount -t btrfs -o defaults,noatime,compress=zstd "/dev/mapper/$LUKS_ROOT_NAME" "$BTRFS_TEMP_MOUNT"
    # Create subvolumes
    echo "creation of subvolumes"
    for sub in activeroot home etc var log tmp; do
        btrfs subvolume create "$BTRFS_TEMP_MOUNT/$sub" || { echo "Failed to create subvolume $sub"; exit 1; }
    done

    # Creating and mounting to root
    echo "Mounting everything to /mnt/gentoo"
    mount -t btrfs -o defaults,noatime,compress=zstd,subvol=activeroot "/dev/mapper/$LUKS_ROOT_NAME" /mnt/gentoo/
    mkdir /mnt/gentoo/{home,etc,var,log,tmp,efi}
    for sub in home etc var log tmp; do
        mount -t btrfs -o defaults,noatime,compress=zstd,subvol=$sub "/dev/mapper/$LUKS_ROOT_NAME" /mnt/gentoo/$sub
    done

}

function stage3() {

	local STAGE3_BASENAME_FINAL
	if [[ ("$GENTOO_ARCH" == "amd64" && "$STAGE3_VARIANT" == *x32*) || ("$GENTOO_ARCH" == "x86" && -n "$GENTOO_SUBARCH") ]]; then
		STAGE3_BASENAME_FINAL="$STAGE3_BASENAME_CUSTOM"
	else
		STAGE3_BASENAME_FINAL="$STAGE3_BASENAME"
	fi

	local STAGE3_RELEASES="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/current-$STAGE3_BASENAME_FINAL/"

	# Download upstream list of files
	CURRENT_STAGE3="$(download_stdout "$STAGE3_RELEASES")" \
		|| { echo "Could not retrieve list of tarballs"; exit 1;}
	# Decode urlencoded strings
	CURRENT_STAGE3=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))' <<< "$CURRENT_STAGE3")
	# Parse output for correct filename
	CURRENT_STAGE3="$(grep -o "\"${STAGE3_BASENAME_FINAL}-[0-9A-Z]*.tar.xz\"" <<< "$CURRENT_STAGE3" \
		| sort -u | head -1)" \
		|| { echo "Could not parse list of tarballs"; exit 1;}
	# Strip quotes
	CURRENT_STAGE3="${CURRENT_STAGE3:1:-1}"
	# File to indiciate successful verification
	CURRENT_STAGE3_VERIFIED="${CURRENT_STAGE3}.verified"

	# Download file if not already downloaded
	if [[ -e $CURRENT_STAGE3_VERIFIED ]]; then
		einfo "$STAGE3_BASENAME_FINAL tarball already downloaded and verified"
	else
		einfo "Downloading $STAGE3_BASENAME_FINAL tarball"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}" "${CURRENT_STAGE3}"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}.DIGESTS" "${CURRENT_STAGE3}.DIGESTS"

		# Import gentoo keys
		einfo "Importing gentoo gpg key"
		local GENTOO_GPG_KEY="$TMP_DIR/gentoo-keys.gpg"
		download "https://gentoo.org/.well-known/openpgpkey/hu/wtktzo4gyuhzu8a4z5fdj3fgmr1u6tob?l=releng" "$GENTOO_GPG_KEY" \
			|| { echo "Could not retrieve gentoo gpg key"; exit 1;}
		gpg --quiet --import < "$GENTOO_GPG_KEY" \
			|| { echo "Could not import gentoo gpg key"; exit 1;}

		# Verify DIGESTS signature
		einfo "Verifying tarball signature"
		gpg --quiet --verify "${CURRENT_STAGE3}.DIGESTS" \
			|| { echo "Signature of '${CURRENT_STAGE3}.DIGESTS' invalid!"; exit 1;}

		# Check hashes
        einfo "Verifying tarball integrity"
        
        # 1. Isolate the SHA512 block, find the tar.xz line, and extract ONLY the raw alphanumeric hash
        raw_hash=$(grep -A 1 'SHA512' "${CURRENT_STAGE3}.DIGESTS" | grep 'tar.xz$' | head -n 1 | awk '{print $1}')
        
        # 2. Reconstruct the exact string sha512sum expects: "<hash>  <exact_filename>" (MUST be two spaces!)
        clean_digest="${raw_hash}  ${CURRENT_STAGE3}"
        sha512sum --check <<< "$clean_digest" \
            || { echo "Checksum mismatch! sha512sum"; exit 1;}
	fi

    echo "Extracting Stage 3 tarball"
    tar xpvf "${CURRENT_STAGE3}" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo \
        || { echo "Failed to extract $STAGE3_FILENAME to /mnt/gentoo"; exit 1; }
    
    echo "Stage 3 tarball extraction completed"

}

function config_system_outside_chroot() {
    
    ROOT_DEV=$(blkid -L BTROOT)
    if [[ -z "$ROOT_DEV" ]]; then
        echo "No partition with LABEL=BTROOT found. Exiting..."
        exit 1
    fi
    echo "Found BTROOT at $ROOT_DEV"

    echo "Editing fstab" 
    cat << EOF > /mnt/gentoo/etc/fstab || { echo "Failed to edit fstab with EOF"; exit 1; }
#Swap
/dev/mapper/cryptswap   none    swap    sw                                           0 0

#Root
LABEL=BTROOT    /       btrfs   defaults,noatime,compress=zstd,subvol=activeroot     0 0
LABEL=BTROOT    /home   btrfs   defaults,noatime,compress=zstd,subvol=home           0 0
LABEL=BTROOT    /etc    btrfs   defaults,noatime,compress=zstd,subvol=etc            0 0
LABEL=BTROOT    /var    btrfs   defaults,noatime,compress=zstd,subvol=var            0 0
LABEL=BTROOT    /log    btrfs   defaults,noatime,compress=zstd,subvol=log            0 0
LABEL=BTROOT    /tmp    btrfs   defaults,noatime,nosuid,nodev,noexec,compress=zstd,subvol=tmp    0 0
EOF

    echo "fstab set"

    echo "Copying DNS info to /mnt/gentoo/etc/"
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    echo "setting up loclale.gen"
    sed -i "s/#$LOCALE/$LOCALE/g" /mnt/gentoo/etc/locale.gen
    # If dualboot uncomment below
    # sed -i "s/clock=\"UTC\"/clock=\"local\"/g" ./etc/conf.d/hwclock
    echo "Changing to keyboard laytout"
    sed -i "s/keymap=\"us\"/keymaps=\"$KEYMAP\"/g" /mnt/gentoo/etc/conf.d/keymaps
    echo "Setting lang and lc_collate"
    echo 'LANG="en_US.UTF-8"' >> /mnt/gentoo/etc/locale.conf
    echo 'LC_COLLATE="C.UTF-8"' >> /mnt/gentoo/etc/locale.conf
    echo "Setting timezone"
    echo "$TIMEZONE" > /mnt/gentoo/etc/timezone

    echo "Succesfully configure basic system"

}

function config_portage() {

    echo "copying over portage from install to /mnt/gentoo/etc/portage/"
    echo "Copying make.conf"
    cp ~/gentoo-install/portage/make.conf /mnt/gentoo/etc/portage/  \
        || { echo "Failed to copy over make.conf"; exit 1;}
    echo "Copying package.use folder"
    cp ~/gentoo-install/portage/package.use/* /mnt/gentoo/etc/portage/package.use \
        || { echo "Failed to copy over portage/package.use/*"; exit 1;}

}

function  gentoo_chroot () {
    local chroot_dir="$1"
    # Copy resolv.conf
	echo "Preparing chroot environment"
	install --mode=0644 /etc/resolv.conf "$chroot_dir/etc/resolv.conf" \
		|| { echo "Could not copy resolv.conf"; exit 1;}

	# Mount virtual filesystems
	einfo "Mounting virtual filesystems"
	(
		mountpoint -q -- "$chroot_dir/proc" || mount -t proc /proc "$chroot_dir/proc" || exit 1
		mountpoint -q -- "$chroot_dir/run"  || {
			mount --rbind /run  "$chroot_dir/run" &&
			mount --make-rslave "$chroot_dir/run"; } || exit 1
		mountpoint -q -- "$chroot_dir/tmp"  || {
			mount --rbind /tmp  "$chroot_dir/tmp" &&
			mount --make-rslave "$chroot_dir/tmp"; } || exit 1
		mountpoint -q -- "$chroot_dir/sys"  || {
			mount --rbind /sys  "$chroot_dir/sys" &&
			mount --make-rslave "$chroot_dir/sys"; } || exit 1
		mountpoint -q -- "$chroot_dir/dev"  || {
			mount --rbind /dev  "$chroot_dir/dev" &&
			mount --make-rslave "$chroot_dir/dev"; } || exit 1
	) || { echo "Could not mount virtual filesystems"; exit 1;}


	# Cache lsblk output, because it doesn't work correctly in chroot (returns almost no info for devices, e.g. empty uuids)
	cache_lsblk_output

	# Execute command
	einfo "Chrooting..."
	EXECUTED_IN_CHROOT=true \
 		DEBUGINFOD_URLS="" \
 		DEBUGINFOD_IMA_CERT_PATH="" \
		TMP_DIR="$TMP_DIR" \
		CACHED_LSBLK_OUTPUT="$CACHED_LSBLK_OUTPUT" \
		exec chroot -- "$chroot_dir" "$GENTOO_INSTALL_REPO_DIR/scripts/dispatch_chroot.sh" "$@" \
			|| { echo "Failed to chroot into '$chroot_dir'."; exit 1;} 

}

function bind_repo_dir() {

	# Use new location by default
	export GENTOO_INSTALL_REPO_DIR="$GENTOO_INSTALL_REPO_BIND"

	# Bind the repo dir to a location in /tmp,
	# so it can be accessed from within the chroot
	mountpoint -q -- "$GENTOO_INSTALL_REPO_BIND" \
		&& return

	# Mount root device
	einfo "Bind mounting repo directory"
	mkdir -p "$GENTOO_INSTALL_REPO_BIND" \
		|| { echo "Could not create mountpoint directory '$GENTOO_INSTALL_REPO_BIND'"; exit 1;}
	mount --bind "$GENTOO_INSTALL_REPO_DIR_ORIGINAL" "$GENTOO_INSTALL_REPO_BIND" \
		|| { echo "Could not bind mount '$GENTOO_INSTALL_REPO_DIR_ORIGINAL' to '$GENTOO_INSTALL_REPO_BIND'"; exit 1;}

}

function mount_efivars() {

	# Skip if already mounted
	mountpoint -q -- "/sys/firmware/efi/efivars" \
		&& return

	# Mount efivars
	einfo "Mounting efivars"
	mount -o remount,rw -t efivarfs efivarfs /sys/firmware/efi/efivars \
		|| { echo "Could not mount efivarfs"; exit 1;}

}
