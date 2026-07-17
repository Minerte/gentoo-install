function main_install() {
    install_stage3
    mount_efivars

    bind_repo_dir

    sleep 5
    export_disk_uuids
    sleep 5

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

    echo "Syncing to DB"
    try emerge --sync --quiet

    env_update

    echo "Emerging sys-*"
    try emerge --verbose sys-kernel/ugrd sys-apps/pciutils sys-fs/cryptsetup \
        sys-fs/btrfs-progs sys-fs/e2fsprogs sys-fs/dosfstools \
	    sys-block/io-scheduler-udev-rules sys-apps/mlocate \
        sys-boot/efibootmgr sys-kernel/installkernel \
        sys-kernel/linux-firmware sys-firmware/sof-firmware \

    echo "Emerging tools"
    try emerge --verbose app-arch/zstd app-crypt/gnupg dev-vcs/git \
        app-portage/gentoolkit app-emulation/virt-firmware
    
    try emerge --oneshot --nodeps app-arch/cpio

    echo "Configure timezone"
    try emerge -v --config sys-libs/timezone-data

    echo "Enable automated EFI"
    try rc-update add kernel-bootcfg-boot-successful default

    install_kernel

    generate_initramfs

    die "Test Completed"

}

function install_kernel() {
    echo "compile kernel"

    try emerge --ask sys-kernel/gentoo-kernel
} 

function generate_initramfs() {
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
    "ugrd.kmod.usb",
    "ugrd.crypto.cryptsetup",
    "ugrd.crypto.gpg",
    "ugrd.fs.btrfs",
]

# Changed from /boot to /efi to match your fstab and disk layout
auto_mounts = ['/efi']

kmod_autodetect_lspci = true

[mounts.efi]
path = '/efi'
uuid = "$efi_uuid"

[cryptsetup.cryptroot]
uuid = "$root_uuid"
key_type = "gpg"
key_file = "/efi/cryptroot_key.luks.gpg"

root_subvol="BTROOT"

[cryptsetup.cryptswap]
uuid = "$swap_uuid"
key_type = "gpg"
key_file = "/efi/cryptswap_key.luks.gpg"
EOF

    einfo "ugrd configuration deployed to $config_file"
}