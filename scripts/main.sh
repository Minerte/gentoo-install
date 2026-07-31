function main_install() {
    install_stage3
    mount_efivars

    bind_repo_dir

    sleep 5
    export_disk_uuids
    sleep 5

    # After disk_format and stage3, ensure /mnt/gentoo/efi exists as a directory
    if [[ ! -d "$ROOT_MOUNTPOINT/efi" ]]; then
        die "EFI directory does not exist at $ROOT_MOUNTPOINT/efi!"
    fi

    gentoo_chroot "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_BIND/install" __install_gentoo_in_chroot
}

function install_stage3() {
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

    setup_disk
    disk_format
    stage3
    config_system_outside_chroot
    config_portage
}

function main_install_gentoo_in_chroot() {
    echo "we are in chroot"

    echo "mounting $EFI_PART to /efi"
    if ! mountpoint -q /efi; then
        mount /dev/disk/by-uuid/"$CHROOT_EFI_UUID" /efi || die "Could not mount EFI by UUID"
        einfo "EFI mounted at /efi"
        sleep 5
        mkdir -p /efi/EFI/Gentoo
        einfo "/efi/Gentoo created"
    else
        einfo "EFI already mounted at /efi"
        sleep 5
    fi

    # FIX: Ensure /efi is mounted on boot (GPG keys live here)
    if ! grep -q "/efi" /etc/fstab; then
        echo "UUID=$CHROOT_EFI_UUID    /efi    vfat   defaults,noatime                                    0 2" >> /etc/fstab
    fi

    # FIX: Kernel command line for uefi-mkconfig / ugrd / LUKS root
    local root_uuid="${CHROOT_ROOT_UUID:-}"
    local root_luks_uuid="${CHROOT_ROOT_UNDERLYING_UUID:-}"
    local swap_uuid="${CHROOT_SWAP_UUID:-}"

    [[ -n "$root_uuid" ]] || die "CHROOT_ROOT_UUID is empty - cannot set root= in kernel cmdline"
    [[ -n "$root_luks_uuid" ]] || die "CHROOT_ROOT_UNDERLYING_UUID is empty - cannot set rd.luks.uuid="

    mkdir -p /etc/kernel
    cat > /etc/kernel/cmdline << 'EOF'
root=UUID=${root_uuid} rd.luks.uuid=${root_luks_uuid} rootflags=subvol=activeroot ro 
resume=UUID=${swap_uuid}
EOF

    # FIX: Explicit USE flags so installkernel knows we want efistub + ugrd
    mkdir -p /etc/portage/package.use
    echo "sys-kernel/installkernel efistub ugrd" > /etc/portage/package.use/installkernel

    echo "Syncing to DB"
    try emerge --sync --quiet

    echo "Configure timezone"
    try emerge -v --config sys-libs/timezone-data

    einfo "Adding cpuflags"
    try emerge --oneshot app-portage/cpuid2cpuflags
    sleep 5

    einfo "Adding cpuflag to make.conf"
    CPU_FLAGS=$(cpuid2cpuflags | cut -d' ' -f2-)
    # 1. If the commented line exists, uncomment it and set the correct flags
    if grep -q "^#CPU_FLAGS_X86=" /etc/portage/make.conf; then
        sed -i "s/^#CPU_FLAGS_X86=.*/CPU_FLAGS_X86=\"${CPU_FLAGS}\"/" /etc/portage/make.conf \
            || die "could not uncomment and set CPU_FLAGS_X86"
        echo "Uncommented and set CPU_FLAGS_X86 in make.conf"

    else
        grep -q "^CPU_FLAGS_X86=" /etc/portage/make.conf
        sed -i "s/^CPU_FLAGS_X86=.*/CPU_FLAGS_X86=\"${CPU_FLAGS}\"/" /etc/portage/make.conf \
            || die "could not update CPU_FLAGS_X86"
        echo "Updated CPU_FLAGS_X86 in make.conf"
    fi

    einfo "Re-emerge ALL system apps"
    try emerge --emptytree -a -1 @installed

    try emerge --oneshot sys-apps/openrc
    echo "merging filesystem"
    try emerge --verbose sys-fs/cryptsetup sys-fs/btrfs-progs \
        sys-fs/e2fsprogs sys-fs/dosfstools app-crypt/gnupg \
        app-arch/zstd

    env_update

    generate_initramfs

    install_kernel

    echo "Emerging tools"
    try emerge --verbose sys-block/io-scheduler-udev-rules \
    sys-apps/mlocate dev-vcs/git net-misc/networkmanager \
    app-shells/bash-completion net-misc/chrony app-admin/sysklogd \
    sys-process/cronie sys-auth/seatd

    enable_service

    echo "Set root password"
    passwd

    einfo "script completed"
}

function install_kernel() {
    echo "compile kernel"
    try emerge --oneshot --nodeps app-arch/cpio

    # Install efibootmgr first so uefi-mkconfig can use it
    try emerge sys-boot/efibootmgr
    try emerge sys-kernel/installkernel sys-kernel/linux-firmware

    try emerge --verbose sys-kernel/gentoo-sources sys-apps/pciutils \
        sys-firmware/sof-firmware app-portage/gentoolkit

    echo "Selecting kernel to set 1"
    try eselect kernel set 1 \
        || die "Could not select kernel source"

    cd /usr/src/linux \
        || die "could not change to /usr/linux"

    # Seed config from the live environment if available
    if [[ -f /proc/config.gz ]]; then
        zcat /proc/config.gz > .config
        make olddefconfig || die "make olddefconfig failed"
        echo "olddefconfig dubug message only"
        sleep 5
    else
        make defconfig || die "make defconfig failed"
        echo "defconfig dubug message only"
        sleep 5
    fi

    # Enable essentials for LUKS + Btrfs + EFI stub booting
    if [[ -f scripts/config ]]; then
        # BTRFS
        ./scripts/config --enable CONFIG_BTRFS_FS
        ./scripts/config --enable CONFIG_BTRFS_FS_POSIX_ACL
        ./scripts/config --enable CONFIG_BTRFS_FS_CHECK_INTEGRITY
        ./scripts/config --enable CONFIG_ZSTD_COMPRESS
        ./scripts/config --enable CONFIG_ZSTD_DECOMPRESS
        ./scripts/config --enable CONFIG_BTRFS_FS_COMPRESS

        # Crypt algorithms
        ./scripts/config --enable CONFIG_DM_CRYPT
        ./scripts/config --enable CONFIG_CRYPTO_MANAGER
        ./scripts/config --enable CONFIG_CRYPTO_AES
        ./scripts/config --enable CONFIG_CRYPTO_XTS
        ./scripts/config --enable CONFIG_CRYPTO_SHA256
        ./scripts/config --enable CONFIG_CRYPTO_SHA512
        ./scripts/config --enable CONFIG_CRYPTO_CRC32C
        ./scripts/config --enable CONFIG_CRC32C_INTEL
        ./scripts/config --enable CONFIG_CRYPTO_USER_API
        ./scripts/config --enable CONFIG_CRYPTO_USER_API_HASH
        ./scripts/config --enable CONFIG_CRYPTO_USER_API_SKCIPHER
        ./scripts/config --enable CONFIG_CRYPTO_DRBG
        ./scripts/config --enable CONFIG_CRYPTO_JITTERENTROPY
        ./scripts/config --enable CONFIG_CRYPTO_XXHASH

        # Device mapper
        ./scripts/config --enable CONFIG_MD
        ./scripts/config --enable CONFIG_BLK_DEV_DM

        # USB and HID
        ./scripts/config --enable CONFIG_USB_SUPPORT
        ./scripts/config --enable CONFIG_USB_XHCI_HCD
        ./scripts/config --enable CONFIG_USB_EHCI_HCD
        ./scripts/config --enable CONFIG_USB_OHCI_HCD
        ./scripts/config --enable CONFIG_USB_UHCI_HCD
        ./scripts/config --enable CONFIG_USB_HID
        ./scripts/config --enable CONFIG_USB_UAS
        ./scripts/config --enable CONFIG_HID
        ./scripts/config --enable CONFIG_HID_GENERIC
        ./scripts/config --enable CONFIG_INPUT
        ./scripts/config --enable CONFIG_INPUT_EVDEV

        # Console and VT
        ./scripts/config --enable CONFIG_VT
        ./scripts/config --enable CONFIG_UNIX98_PTYS
        ./scripts/config --enable CONFIG_TTY

        # fat and vfat
        ./scripts/config --enable CONFIG_FAT_FS
        ./scripts/config --enable CONFIG_VFAT_FS
        ./scripts/config --enable CONFIG_NLS_CODEPAGE_437
        ./scripts/config --enable CONFIG_NLS_ISO8859_1

        # SATA / SCSI
        ./scripts/config --enable CONFIG_ATA
        ./scripts/config --enable CONFIG_SATA_AHCI
        ./scripts/config --enable CONFIG_SCSI
        ./scripts/config --enable CONFIG_BLK_DEV_SD
        # EFI
        ./scripts/config --enable CONFIG_EFI
        ./scripts/config --enable CONFIG_EFIVAR_FS
        ./scripts/config --enable CONFIG_EFI_PARTITION
        ./scripts/config --enable CONFIG_EFI_RUNTIME_MAP
        ./scripts/config --enable CONFIG_EFI_STUB
        ./scripts/config --enable CONFIG_PROC_FS

        # AMD platform (x670e / Ryzen 9950x)
        ./scripts/config --enable CONFIG_AMD_NB
        ./scripts/config --enable CONFIG_X86_AMD_PLATFORM_DEVICE
        ./scripts/config --enable CONFIG_AMD_PMC

        # NVME
        ./scripts/config --module CONFIG_NVME_CORE
        ./scripts/config --enable CONFIG_BLK_DEV_NVME
        ./scripts/config --module CONFIG_NVME_FABRICS
        ./scripts/config --module CONFIG_NVME_FC
        ./scripts/config --module CONFIG_NVME_TCP
        ./scripts/config --module CONFIG_NVME_KEYRING
        ./scripts/config --module CONFIG_NVME_AUTH
        ./scripts/config --module CONFIG_NVME_TARGET
        ./scripts/config --module CONFIG_NVME_TARGET_LOOP
        ./scripts/config --module CONFIG_NVME_TARGET_FC
        ./scripts/config --module CONFIG_NVME_TARGET_TCP
        ./scripts/config --module CONFIG_NVME_TARGET_AUTH

        # EXTRA
        ./scripts/config --enable CONFIG_DM_INIT
        ./scripts/config --enable CONFIG_DAX
        ./scripts/config --enable CONFIG_RD_ZSTD

        sleep 5
        make olddefconfig || die "make olddefconfig failed after scripts/config"
        sleep 5
    fi

    echo "Compiling kernel with ${NPROC} jobs"
    try make -j"${NPROC}" || die "Kernel compilation failed"
    sleep 5

    echo "Installing modules"
    try make modules_install || die "make modules_install failed"
    sleep 5

    # Determine the kernel version
    local kver
    kver=$(make -C /usr/src/linux -s kernelrelease 2>/dev/null) \
        || kver=$(cat /usr/src/linux/include/config/kernel.release 2>/dev/null) \
        || die "Could not detect kernel version from /usr/src/linux"

    cp /usr/src/linux/arch/x86_64/boot/bzImage "/efi/EFI/Gentoo/vmlinuz-${kver}-gentoo.efi" \
        || die "Could not copy bzImage to /efi/EFI/Gentoo/vmlinuz-$kver-gentoo.efi"
    einfo "bzImage to /efi/EFI/Gentoo/vmlinuz-$kver-gentoo.efi copied successfully"
    sleep 5

    echo "Installing kernel (triggers installkernel hooks -> ugrd -> uefi-mkconfig)"
    try make install || die "make install failed"
    sleep 10

    setup_efistub_boot

    cd \
        || die "Could not change to root dir"
}

function generate_initramfs() {
    echo "Compiling initramfs"
    try emerge --verbose sys-kernel/ugrd

    echo  "Generating initramfs"
    sleep 5

    local efi_uuid="${CHROOT_EFI_UUID:-}"
    local root_uuid="${CHROOT_ROOT_UNDERLYING_UUID:-}"
    local swap_uuid="${CHROOT_SWAP_UNDERLYING_UUID:-}"

    [[ -n "$efi_uuid" ]] || die "EFI UUID is empty"
    [[ -n "$root_uuid" ]] || die "Root UUID is empty"
    [[ -n "$swap_uuid" ]] || die "Swap UUID is empty"

    # Check for GPG keys in /efi (where fulldisk_encryption.sh actually puts them)
    [[ -f "/efi/cryptroot_key.luks.gpg" ]] || die "GPG root key not found at /efi/cryptroot_key.luks.gpg"

    local config_file="/etc/ugrd/config.toml"
    mkdir -p "$(dirname "$config_file")"

    cat > "$config_file" << EOF
modules = [
    "ugrd.base.console",
    "ugrd.base.keymap",
    "ugrd.kmod.usb",
    "ugrd.crypto.cryptsetup",
    "ugrd.crypto.gpg",
    "ugrd.fs.btrfs"
]

keymap_file = "/usr/share/keymaps/i386/qwerty/sv-latin1.map.gz"
kmod_autodetect_lspci = true

# Changed from /boot to /efi to match your fstab and disk layout
auto_mounts = ['/efi']

[mounts.efi]
path = '/efi'
uuid = "$efi_uuid"

[cryptsetup.cryptswap]
uuid = "$swap_uuid"
key_type = "gpg"
key_file = "/efi/cryptswap_key.luks.gpg"

[cryptsetup.cryptroot]
uuid = "$root_uuid"
key_type = "gpg"
key_file = "/efi/cryptroot_key.luks.gpg"
EOF

    einfo "ugrd configuration deployed to $config_file"
}

function enable_service() {
    echo "Enable services"

    try rc-update del dhcpcd default || die "rc-update del dhcpcd default failed"
    try rc-service dhcpcd stop || die "rc-service dhcpcd stop failed"
    
    try rc-update add NetworkManager default || die "rc-update add NetworkManager default failed"
    try rc-update add chronyd default || die "rc-update add chronyd default failed"
    try rc-update add cronie default || die "rc-update add cronie default failed"
    try rc-update add seatd default || die "rc-updtae add seatd default failed"
    try rc-update add hostname boot || die "rc-update add hostname boot"
    try rc-update add dbus default || die "rc-update add dbus default failed"
    try rc-update add keymaps boot || die "rc-update add keymaps boot failed"
}

function setup_efistub_boot() {
    einfo "Setting up EFISTUB boot entry with efibootmgr"

    # --- 1. Detect kernel version ---
    local kver
    kver=$(make -C /usr/src/linux -s kernelrelease 2>/dev/null) \
        || kver=$(cat /usr/src/linux/include/config/kernel.release 2>/dev/null) \
        || die "Could not detect kernel version from /usr/src/linux"

    einfo "Detected kernel version: $kver"

    # --- 2. Find the actual files on the ESP (installed by make install + ugrd) ---
    local efi_vmlinuz efi_initramfs
    efi_vmlinuz=$(find /efi -maxdepth 3 -name "vmlinuz-*" -printf '%P\n' 2>/dev/null | sort | tail -n1)
    efi_initramfs=$(find /efi -maxdepth 3 -name "initramfs-*.img" -printf '%P\n' 2>/dev/null | sort | tail -n1)

    [[ -n "$efi_vmlinuz" ]] || die "No vmlinuz found on /efi"
    [[ -n "$efi_initramfs" ]] || ewarn "No initramfs found on /efi (continuing without initrd=)"

    # Convert forward slashes to EFI backslashes
    local loader_path initrd_path
    loader_path="\EFI\${efi_vmlinuz//\//\\}"
    [[ -n "$efi_initramfs" ]] && initrd_path="\\${efi_initramfs//\//\\}"

    einfo "ESP loader:  $loader_path"
    einfo "ESP initrd:  ${initrd_path:-<none>}"

    # --- 3. Detect EFI disk and partition number from CHROOT_EFI_UUID ---
    local efi_part_dev efi_disk efi_partnum
    efi_part_dev=$(readlink -f "/dev/disk/by-uuid/${CHROOT_EFI_UUID}")
    [[ -b "$efi_part_dev" ]] || die "EFI partition not found by UUID: $CHROOT_EFI_UUID"

    efi_disk="/dev/$(lsblk -dno pkname "$efi_part_dev")"
    efi_partnum=$(cat "/sys/class/block/$(basename "$efi_part_dev")/partition" 2>/dev/null) \
        || efi_partnum=$(lsblk -no MAJ:MIN "$efi_part_dev" | awk -F: '{print $2}')

    [[ -b "$efi_disk" ]] || die "Could not resolve EFI disk for $efi_part_dev"
    [[ "$efi_partnum" =~ ^[0-9]+$ ]] || die "Could not resolve EFI partition number"

    einfo "EFI disk:    $efi_disk"
    einfo "EFI part:    $efi_partnum"

    # --- 4. Build kernel cmdline dynamically ---
    local root_uuid="${CHROOT_ROOT_UUID:-}"
    local root_luks_uuid="${CHROOT_ROOT_UNDERLYING_UUID:-}"
    local swap_uuid="${CHROOT_SWAP_UUID:-}"

    [[ -n "$root_uuid" ]] || die "CHROOT_ROOT_UUID is empty"
    [[ -n "$root_luks_uuid" ]] || die "CHROOT_ROOT_UNDERLYING_UUID is empty"

    local cmdline="root=UUID=${root_uuid} rd.luks.uuid=${root_luks_uuid} rootflags=subvol=activeroot ro"
    [[ -n "$swap_uuid" ]] && cmdline+=" resume=UUID=${swap_uuid}"

    einfo "Kernel cmdline: $cmdline"

    # --- 5. Clean up old Gentoo entries to avoid duplicates ---
    local old_entries
    old_entries=$(efibootmgr | awk '/Boot[0-9A-F]{4}\*? Gentoo/ {gsub(/Boot|\*/,"",$1); print $1}')
    for entry in $old_entries; do
        einfo "Removing old boot entry: Boot$entry"
        efibootmgr --bootnum "$entry" --delete-bootnum >/dev/null 2>&1 || true
    done

    # --- 6. Create the new entry ---
    local efiboot_args=(
        --create
        --disk "$efi_disk"
        --part "$efi_partnum"
        --label "Gentoo"
        --loader "$loader_path"
    )

    if [[ -n "$initrd_path" ]]; then
        efiboot_args+=(--unicode "initrd=${initrd_path} ${cmdline}")
    else
        efiboot_args+=(--unicode "$cmdline")
    fi

    efibootmgr "${efiboot_args[@]}" || die "efibootmgr failed to create boot entry"

    einfo "EFISTUB boot entry created successfully"
    efibootmgr | grep -i gentoo || true
}