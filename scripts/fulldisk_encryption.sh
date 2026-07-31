function cache_lsblk_output() {
	CACHED_LSBLK_OUTPUT="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID)" \
		|| die "Error while executing lsblk to cache output"
}

function die() {
	eerror "$*"
	[[ -v GENTOO_INSTALL_REPO_SCRIPT_PID && $$ -ne $GENTOO_INSTALL_REPO_SCRIPT_PID ]] \
		&& kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"
	exit 1
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

function eerror() {
	echo "[1;31merror:[m $*" >&2
}

function einfo() {
	echo "[[1m+[m] [1;33m$*[m"
}

function env_update() {
    env-update \
        || die "Error in env-update"
    export DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-}"
    export DEBUGINFOD_IMA_CERT_PATH="${DEBUGINFOD_IMA_CERT_PATH:-}"
    source /etc/profile \
        || die "Could not source /etc/profile"
}

function flush_stdin() {
	local empty_stdin
	# Unused variable is intentional.
	# shellcheck disable=SC2034
	while read -r -t 0.01 empty_stdin; do true; done
}

function init_bash() {
	source /etc/profile
	umask 0077
	export PS1='(chroot) \[[0;31m\]\u\[[1;31m\]@\h \[[1;34m\]\w \[[m\]\$ \[[m\]'
}; export -f init_bash

function mkdir_or_die() {
	# shellcheck disable=SC2174
	mkdir -m "$1" -p "$2" \
		|| die "Could not create directory '$2'"
}

function try() {
	local response
	local cmd_status
	local prompt_parens="([1mS[mhell/[1mr[metry/[1ma[mbort/[1mc[montinue/[1mp[mrint)"

	# Outer loop, allows us to retry the command
	while true; do
		# Try command
		"$@"
		cmd_status="$?"

		if [[ $cmd_status != 0 ]]; then
			echo "[1;31m * Command failed: [1;33m\$[m $*"
			echo "Last command failed with exit code $cmd_status"

			# Prompt until input is valid
			while true; do
				echo -n "Specify next action $prompt_parens "
				flush_stdin
				read -r response \
					|| die "Error in read"
				case "${response,,}" in
					''|s|shell)
						echo "You will be prompted for action again after exiting this shell."
						/bin/bash --init-file <(echo "init_bash")
						;;
					r|retry) continue 2 ;;
					a|abort) die "Installation aborted" ;;
					c|continue) return 0 ;;
					p|print) echo "[1;33m\$[m $*" ;;
					*) ;;
				esac
			done
		fi

		return
	done
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
    read -p "Does the layout match your expectations? Type 'YES' to continue: " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo "Aborting script. No filesystems were created."
        exit 1
    fi

    echo "Verification passed. Proceeding to filesystem creation..."
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

    # --- Temporary EFI mount for GPG key creation ---
    local EFI_TEMP_MOUNT="/tmp/efi-temp"
    echo "Creating temporary EFI mount at $EFI_TEMP_MOUNT"
    mkdir -p "$EFI_TEMP_MOUNT" || die "Could not create dir $EFI_TEMP_MOUNT"
    mount "$EFI_PART" "$EFI_TEMP_MOUNT" || die "Failed to mount $EFI_PART to $EFI_TEMP_MOUNT"

    cd "$EFI_TEMP_MOUNT" || die "Failed to change dir to $EFI_TEMP_MOUNT"

    einfo "Creating encryption for swap"
    dd bs=8388608 count=1 if=/dev/urandom | gpg --symmetric --cipher-algo AES256 --output cryptswap_key.luks.gpg \
        || die "Could not generate GPG encrypted swap keyfile"

    if [[ -f "cryptswap_key.luks.gpg" ]]; then
        einfo "cryptswap_key.luks.gpg created (size: $(stat -c %s cryptswap_key.luks.gpg) bytes)"
    else
        die "cryptswap_key.luks.gpg was not created!"
    fi

    # Use the GPG keyfile to format LUKS partition
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
                || die "Could not create luks on $SWAP_PART"

    sleep 5

    gpg --batch --yes --decrypt "cryptswap_key.luks.gpg" | cryptsetup open --type luks2 \
            "$SWAP_PART" "$LUKS_SWAP_NAME" \
            --key-file=- \
                ||  die "Could not open luks encrypted device"

    echo "SWAP partition encrypted and open at /dev/mapper/$LUKS_SWAP_NAME"

    echo "Formating swap"
    mkswap "/dev/mapper/$LUKS_SWAP_NAME"
    swapon "/dev/mapper/$LUKS_SWAP_NAME"

    einfo "Creating encryption for root"
    dd bs=8388608 count=1 if=/dev/urandom | gpg --symmetric --cipher-algo AES256 --output cryptroot_key.luks.gpg \
        || die "Could not generate GPG encrypted root keyfile"

    if [[ -f "cryptroot_key.luks.gpg" ]]; then
        einfo "cryptroot_key.luks.gpg created (size: $(stat -c %s cryptroot_key.luks.gpg) bytes)"
    else
        die "cryptroot_key.luks.gpg was not created!"
    fi

    # Use the GPG keyfile to format LUKS partition
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
                || die "Could not create luks on $ROOT_PART"

    sleep 5

    gpg --batch --yes --decrypt cryptroot_key.luks.gpg \
        | cryptsetup open --type luks2 \
            "$ROOT_PART" "$LUKS_ROOT_NAME" \
            --key-file=- \
                || die "Could not open luks encrypted device"

    echo "Root partition encrypted and open at /dev/mapper/$LUKS_ROOT_NAME"

    echo "Change dir back to /"
    cd || die "Failed to change dir to /"

    # --- Format root as BTRFS ---
    echo "Formating $ROOT_PART"
    mkfs.btrfs -L BTROOT "/dev/mapper/$LUKS_ROOT_NAME" || die "Failed to create btrfs"

    # --- Temporarily mount top-level ONLY to create subvolumes ---
    echo "Temporarily mounting filesystem to $BTRFS_TEMP_MOUNT for subvolume creation"
    mkdir -p "$BTRFS_TEMP_MOUNT" || die "Could not create dir $BTRFS_TEMP_MOUNT"
    mount -t btrfs -o defaults,noatime,compress=zstd "/dev/mapper/$LUKS_ROOT_NAME" "$BTRFS_TEMP_MOUNT"

    echo "creation of subvolumes"
    for sub in activeroot home etc var log tmp; do
        btrfs subvolume create "$BTRFS_TEMP_MOUNT/$sub" || die "Failed to create subvolume $sub"
    done

    # Unmount top-level immediately after subvolume creation
    echo "Unmounting $BTRFS_TEMP_MOUNT"
    umount "$BTRFS_TEMP_MOUNT" || "Failed to unmount $BTRFS_TEMP_MOUNT"

    # --- Mount activeroot DIRECTLY to /mnt/gentoo (the chroot target) ---
    echo "Mounting activeroot subvolume to $ROOT_MOUNTPOINT"
    mkdir -p "$ROOT_MOUNTPOINT" || die "Could not create dir $ROOT_MOUNTPOINT"
    mount -t btrfs -o defaults,noatime,compress=zstd,subvol=activeroot "/dev/mapper/$LUKS_ROOT_NAME" "$ROOT_MOUNTPOINT"

    # --- Create mount points INSIDE activeroot for other subvolumes and EFI ---
    echo "Creating mount points in $ROOT_MOUNTPOINT"
    mkdir -p "$ROOT_MOUNTPOINT"/{home,etc,var,log,tmp,efi} || die "Could not create directories in $ROOT_MOUNTPOINT"

    # Mount other subvolumes
    echo "Mounting subvolumes"
    for sub in home etc var log tmp; do
        mount -t btrfs -o defaults,noatime,compress=zstd,subvol=$sub "/dev/mapper/$LUKS_ROOT_NAME" "$ROOT_MOUNTPOINT/$sub"
    done

    # DO NOT mount EFI here — let the chroot script handle it
    # This keeps /mnt/gentoo/efi as an empty directory inside activeroot
    echo "EFI directory created at $ROOT_MOUNTPOINT/efi (will be mounted inside chroot)"

    echo "Disk format completed successfully"
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
		|| die "Could not retrieve list of tarballs"
	# Decode urlencoded strings
	CURRENT_STAGE3=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))' <<< "$CURRENT_STAGE3")
	# Parse output for correct filename
	CURRENT_STAGE3="$(grep -o "\"${STAGE3_BASENAME_FINAL}-[0-9A-Z]*.tar.xz\"" <<< "$CURRENT_STAGE3" \
		| sort -u | head -1)" \
		|| die "Could not parse list of tarballs"
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
			|| die "Could not retrieve gentoo gpg key"
		gpg --quiet --import < "$GENTOO_GPG_KEY" \
			|| die "Could not import gentoo gpg key"

		# Verify DIGESTS signature
		einfo "Verifying tarball signature"
		gpg --quiet --verify "${CURRENT_STAGE3}.DIGESTS" \
			|| die "Signature of '${CURRENT_STAGE3}.DIGESTS' invalid!"

		# Check hashes
        einfo "Verifying tarball integrity"

        # 1. Isolate the SHA512 block, find the tar.xz line, and extract ONLY the raw alphanumeric hash
        raw_hash=$(grep -A 1 'SHA512' "${CURRENT_STAGE3}.DIGESTS" | grep 'tar.xz$' | head -n 1 | awk '{print $1}')

        # 2. Reconstruct the exact string sha512sum expects: "<hash>  <exact_filename>" (MUST be two spaces!)
        clean_digest="${raw_hash}  ${CURRENT_STAGE3}"
        sha512sum --check <<< "$clean_digest" \
            || die "Checksum mismatch! sha512sum"
	fi

	echo "sleep... 5 seconds"
	sleep 5

    einfo "Extracting Stage 3 tarball"
    tar xpvf "${CURRENT_STAGE3}" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo \
        || die "Failed to extract $STAGE3_FILENAME to /mnt/gentoo"

    # --- Add this block ---
    echo "Verifying Stage 3 extraction..."
    if [[ ! -x /mnt/gentoo/sbin/init ]]; then
        die "Stage 3 extraction incomplete: /mnt/gentoo/sbin/init is missing or not executable"
    fi
    ls -la /mnt/gentoo/sbin/init
    # --- End block ---

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
    cat << EOF > /mnt/gentoo/etc/fstab || die "Failed to edit fstab with EOF"
#SWAP
/dev/mapper/cryptswap   none    swap    sw                                                       0 0

#ROOT
LABEL=BTROOT    /       btrfs   defaults,noatime,compress=zstd,subvol=activeroot                 0 0
LABEL=BTROOT    /home   btrfs   defaults,noatime,compress=zstd,subvol=home                       0 0
LABEL=BTROOT    /etc    btrfs   defaults,noatime,compress=zstd,subvol=etc                        0 0
LABEL=BTROOT    /var    btrfs   defaults,noatime,compress=zstd,subvol=var                        0 0
LABEL=BTROOT    /log    btrfs   defaults,noatime,compress=zstd,subvol=log                        0 0
LABEL=BTROOT    /tmp    btrfs   defaults,noatime,nosuid,nodev,noexec,compress=zstd,subvol=tmp    0 0

# EFI
EOF

    einfo "fstab set"

    echo "Copying DNS info to /mnt/gentoo/etc/"
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    einfo "setting up loclale.gen"
    sed -i "s/#$LOCALE/$LOCALE/g" /mnt/gentoo/etc/locale.gen
    # If dualboot uncomment below
    # sed -i "s/clock=\"UTC\"/clock=\"local\"/g" ./etc/conf.d/hwclock
    einfo "Changing to keyboard laytout"
    echo "keymap=\"$KEYMAP\"" > /mnt/gentoo/etc/conf.d/keymaps
    einfo "Setting lang and lc_collate"
    echo 'LANG="en_US.UTF-8"' >> /mnt/gentoo/etc/locale.conf
    echo 'LC_COLLATE="C.UTF-8"' >> /mnt/gentoo/etc/locale.conf
    einfo "Setting timezone"
    echo "$TIMEZONE" > /mnt/gentoo/etc/timezone
    einfo "Setting hostname to $HOSTNAME"
    # Set hostname
    echo "hostname=\"$HOSTNAME\"" > /mnt/gentoo/etc/conf.d/hostname
    # Also update /etc/hosts with the hostname
    cat >> /mnt/gentoo/etc/hosts << EOF
127.0.0.1   $HOSTNAME localhost
::1         $HOSTNAME localhost
EOF

    einfo "Succesfully configure basic system"
}

function config_portage() {
    einfo "Copying over portage from install to /mnt/gentoo/etc/portage/"
    echo "Copying make.conf"
    cp ~/gentoo-install/portage/make.conf /mnt/gentoo/etc/portage/  \
        || die "Failed to copy over make.conf"
    echo "Copying package.use folder"
    cp ~/gentoo-install/portage/package.use/* /mnt/gentoo/etc/portage/package.use \
        || die "Failed to copy over portage/package.use/*"
}

function gentoo_chroot () {
    if [[ $# -eq 1 ]]; then
        einfo "To later unmount all virtual filesystems, simply use umount -l ${1@Q}"
        gentoo_chroot "$1" /bin/bash --init-file <(echo 'init_bash')
        return
    fi

    [[ ${EXECUTED_IN_CHROOT-false} == "false" ]] \
        || die "Already in chroot"

    local chroot_dir="$1"
    shift

    bind_repo_dir

    # Copy resolv.conf
    einfo "Preparing chroot environment"
    install --mode=0644 /etc/resolv.conf "$chroot_dir/etc/resolv.conf" \
        || die "Could not copy resolv.conf"

    # Mount virtual filesystems
    einfo "Mounting virtual filesystems"
    (
        mountpoint -q -- "$chroot_dir/proc" || mount -t proc /proc "$chroot_dir/proc" || exit 1
        mountpoint -q -- "$chroot_dir/run"  || {
            mount --rbind /run  "$chroot_dir/run" &&
            mount --make-rslave "$chroot_dir/run"; } || exit 1
        # Force bind-mount host /tmp over chroot /tmp (ignore existing mount)
        umount -l "$chroot_dir/tmp" 2>/dev/null
        mount --rbind /tmp "$chroot_dir/tmp" || exit 1
        mount --make-rslave "$chroot_dir/tmp" || exit 1
        mountpoint -q -- "$chroot_dir/sys"  || {
            mount --rbind /sys  "$chroot_dir/sys" &&
            mount --make-rslave "$chroot_dir/sys"; } || exit 1
        mountpoint -q -- "$chroot_dir/dev"  || {
            mount --rbind /dev  "$chroot_dir/dev" &&
            mount --make-rslave "$chroot_dir/dev"; } || exit 1
    ) || die "Could not mount virtual filesystems"

    cache_lsblk_output
    CHROOT_SCRIPT_PATH="/tmp/gentoo-install-repo/scripts/dispatch_chroot.sh"

    # Verify the script exists inside the chroot (after /tmp is mounted)
    if [[ ! -f "$chroot_dir$CHROOT_SCRIPT_PATH" ]]; then
        # Debug: list what's actually there
        echo "Contents of $chroot_dir/tmp/gentoo-install-repo/scripts/:"
        ls -la "$chroot_dir/tmp/gentoo-install-repo/scripts/" 2>/dev/null || echo "Directory not accessible"
        die "Script not found at $chroot_dir$CHROOT_SCRIPT_PATH"
    fi

    einfo "Chrooting..."
    EXECUTED_IN_CHROOT=true \
        DEBUGINFOD_URLS="" \
        DEBUGINFOD_IMA_CERT_PATH="" \
        TMP_DIR="$TMP_DIR" \
        CACHED_LSBLK_OUTPUT="$CACHED_LSBLK_OUTPUT" \
        CHROOT_EFI_UUID="$CHROOT_EFI_UUID" \
        CHROOT_ROOT_UUID="$CHROOT_ROOT_UUID" \
        CHROOT_ROOT_UNDERLYING_UUID="$CHROOT_ROOT_UNDERLYING_UUID" \
        CHROOT_SWAP_UUID="$CHROOT_SWAP_UUID" \
        CHROOT_SWAP_UNDERLYING_UUID="$CHROOT_SWAP_UNDERLYING_UUID" \
        exec chroot -- "$chroot_dir" "$CHROOT_SCRIPT_PATH" "$@" \
        || die "Failed to chroot into '$chroot_dir'."
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
        || die "Could not create mountpoint directory '$GENTOO_INSTALL_REPO_BIND'"
    mount --bind "$GENTOO_INSTALL_REPO_DIR_ORIGINAL" "$GENTOO_INSTALL_REPO_BIND" \
        || die "Could not bind mount '$GENTOO_INSTALL_REPO_DIR_ORIGINAL' to '$GENTOO_INSTALL_REPO_BIND'"

    # Verify the bind mount worked and the script exists
    if [[ ! -f "$GENTOO_INSTALL_REPO_BIND/scripts/dispatch_chroot.sh" ]]; then
        die "dispatch_chroot.sh not found in bind mount at $GENTOO_INSTALL_REPO_BIND/scripts/dispatch_chroot.sh"
    fi
    einfo "Bind mount verified: dispatch_chroot.sh exists"
}
function mount_efivars() {
	# Skip if already mounted
	mountpoint -q -- "/sys/firmware/efi/efivars" \
		&& return

	# Mount efivars
	einfo "Mounting efivars"
	mount -o remount,rw -t efivarfs efivarfs /sys/firmware/efi/efivars \
		|| die "Could not mount efivarfs"
}

function export_disk_uuids() {
    einfo "Resolving disk UUIDs on host for chroot environment"

    # 1. EFI UUID (FAT32 filesystem)
    CHROOT_EFI_UUID="$(blkid -s UUID -o value "$EFI_PART")"
    export CHROOT_EFI_UUID
    [[ -n "$CHROOT_EFI_UUID" ]] || die "Failed to resolve EFI UUID for $EFI_PART"

    # 2. Root underlying LUKS partition UUID (for rd.luks.uuid=)
    CHROOT_ROOT_UNDERLYING_UUID="$(blkid -s UUID -o value "$ROOT_PART")"
    export CHROOT_ROOT_UNDERLYING_UUID
    [[ -n "$CHROOT_ROOT_UNDERLYING_UUID" ]] || die "Failed to resolve underlying root UUID for $ROOT_PART"

    # 2b. Root BTRFS filesystem UUID inside decrypted LUKS (for root=)
    CHROOT_ROOT_UUID="$(blkid -s UUID -o value "/dev/mapper/$LUKS_ROOT_NAME")"
    export CHROOT_ROOT_UUID
    [[ -n "$CHROOT_ROOT_UUID" ]] || die "Failed to resolve root BTRFS UUID for /dev/mapper/$LUKS_ROOT_NAME"

    # 3. Swap underlying LUKS partition UUID
    CHROOT_SWAP_UNDERLYING_UUID="$(blkid -s UUID -o value "$SWAP_PART")"
    export CHROOT_SWAP_UNDERLYING_UUID
    [[ -n "$CHROOT_SWAP_UNDERLYING_UUID" ]] || die "Failed to resolve underlying swap UUID for $SWAP_PART"

    # 3b. Swap filesystem UUID inside decrypted LUKS (for resume=)
    CHROOT_SWAP_UUID="$(blkid -s UUID -o value "/dev/mapper/$LUKS_SWAP_NAME")"
    export CHROOT_SWAP_UUID
    [[ -n "$CHROOT_SWAP_UUID" ]] || die "Failed to resolve swap UUID for /dev/mapper/$LUKS_SWAP_NAME"

    einfo "Disk UUIDs resolved successfully"
    einfo "  EFI:           $CHROOT_EFI_UUID"
    einfo "  Root LUKS:     $CHROOT_ROOT_UNDERLYING_UUID"
    einfo "  Root BTRFS:    $CHROOT_ROOT_UUID"
    einfo "  Swap LUKS:     $CHROOT_SWAP_UNDERLYING_UUID"
    einfo "  Swap:          $CHROOT_SWAP_UUID"
}