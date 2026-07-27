function main_install() {
    install_stage3
    mount_efivars

    bind_repo_dir

    sleep 5
    export_disk_uuids
    sleep 5

    # After disk_format and stage3, ensure /mnt/gentoo/efi is mounted
    if ! mountpoint -q "$ROOT_MOUNTPOINT/efi"; then
        die "EFI partition is not mounted at $ROOT_MOUNTPOINT/efi!"
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
        mkdir -p /efi/Gentoo
        einfo "/efi/Gentoo created"
    else
        einfo "EFI already mounted at /efi"
        sleep 5
    fi

    # FIX: Ensure /efi is mounted on boot (GPG keys live here)
    if ! grep -q "/efi" /etc/fstab; then
        echo "UUID=$CHROOT_EFI_UUID  /efi  vfat  defaults,noatime  0 2" >> /etc/fstab
    fi

    # FIX: Kernel command line for uefi-mkconfig / ugrd / LUKS root
    mkdir -p /etc/kernel
    cat > /etc/kernel/cmdline << 'EOF'
root=/dev/mapper/cryptroot rootfstype=btrfs rootflags=subvol=activeroot
EOF

    # FIX: Explicit USE flags so installkernel knows we want efistub + ugrd
    mkdir -p /etc/portage/package.use
    echo "sys-kernel/installkernel efistub ugrd" > /etc/portage/package.use/installkernel

    echo "Syncing to DB"
    try emerge --sync --quiet

    echo "merging filesystem"
    try emerge --verbose sys-fs/cryptsetup ys-fs/btrfs-progs \
        sys-fs/e2fsprogs sys-fs/dosfstools
    
    try emerge --verbose app-arch/zstd app-crypt/gnupg

    env_update

    generate_initramfs

    install_kernel

    echo "Emerging tools"
    try emerge --verbose sys-block/io-scheduler-udev-rules \
    sys-apps/mlocate dev-vcs/git 

    echo "Configure timezone"
    try emerge -v --config sys-libs/timezone-data

    die "Test Completed"

}

function install_kernel() {
    echo "compile kernel"
    try emerge --oneshot --nodeps app-arch/cpio

    # Install efibootmgr first so uefi-mkconfig can use it
    try emerge sys-boot/efibootmgr

    try emerge sys-kernel/installkernel sys-kernel/linux-firmware

    try emerge --verbose sys-kernel/gentoo-kernel sys-apps/pciutils \
        sys-kernel/linux-firmware sys-firmware/sof-firmware \
        app-portage/gentoolkit

        # Change to gentoo-sources kernel 
} 

function generate_initramfs() {
    echo "Compiling initramfs"
    try emerge --verbose sys-kernel/ugrd

    echo  "Generating initramfs"

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
    "ugrd.kmod.usb",
    "ugrd.crypto.cryptsetup",
    "ugrd.crypto.gpg",
    "ugrd.fs.btrfs"
]

subvol_selector = true
pio_compression = "zstd"
# kmod_autodetect_lspci = true

kmod_init = ["dm_crypt", "nvme", "btrfs", "xhci_pci", "usb_storage", "vfat"]

# Changed from /boot to /efi to match your fstab and disk layout
auto_mounts = ['/efi']

[mounts.efi]
path = '/efi'
uuid = "$efi_uuid"

[cryptsetup.cryptroot]
uuid = "$root_uuid"
key_type = "gpg"
key_file = "/efi/cryptroot_key.luks.gpg"

[cryptsetup.cryptswap]
uuid = "$swap_uuid"
key_type = "gpg"
key_file = "/efi/cryptswap_key.luks.gpg"
EOF

    einfo "ugrd configuration deployed to $config_file"

    einfo "updating make.conf for kernel to use ugrd"

    # THIS failed becuase of spacing issue in make.conf
    # just add it to make.conf and then uncomment it
    # test sys-kernel/gentoo-kernel -initramfs

    ugrd --kver 6.18.29-gentoo-dist-hardened /efi/initramfs-6.18.39-hardened.img

}