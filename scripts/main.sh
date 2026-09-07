function main_install() {
    install_stage3
    export_disk_uuids

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
    # Remove the root password, making the account accessible for automated
    # tasks during the period of installation.
    einfo "Clearing root password"
    passwd -d root \
		|| die "Could not change root password"

    echo "mounting $EFI_PART to /efi"
    mount /dev/disk/by-uuid/"$CHROOT_EFI_UUID" /efi || die "Could not mount EFI by UUID"
    einfo "EFI mounted at /efi"
    mkdir -p /efi/EFI/Gentoo || die "Could not create /efi/EFI/Gentoo"
    mkdir -p /efi/EFI/BOOT || die "Could not create /efi/EFI/BOOT"
    einfo "/efi/Gentoo created"

    # FIX: Ensure /efi is mounted on boot (GPG keys live here)
    einfo "Adding EFI UUID TO SWAP"
    if ! grep -q "/efi" /etc/fstab; then
        echo "UUID=$CHROOT_EFI_UUID  /efi     vfat   defaults,noatime                                             0 2" >> /etc/fstab
    fi

    echo "Syncing portage tree"
    try emerge-webrsync
    sleep 5
    try emerge --sync --quiet

    configure_system

    einfo "Adding cpuflags"
    try emerge --oneshot app-portage/cpuid2cpuflags
    sleep 5

    einfo "Adding cpuflag to make.conf"
    CPU_FLAGS=$(cpuid2cpuflags | cut -d' ' -f2-)
    # 1. If the commented line exists, uncomment it and set the correct flags
    sed -i "s/^#CPU_FLAGS_X86=.*/CPU_FLAGS_X86=\"${CPU_FLAGS}\"/" /etc/portage/make.conf \
        || die "could not uncomment and set CPU_FLAGS_X86"
    echo "Uncommented and set CPU_FLAGS_X86 in make.conf"
    sleep 5

    einfo "Re-emerge ALL system apps"
    try emerge --emptytree -1 @installed

    echo "merging filesystem"
    try emerge --verbose sys-fs/cryptsetup sys-fs/btrfs-progs \
        sys-fs/e2fsprogs sys-fs/dosfstools app-crypt/gnupg \
        app-arch/zstd sys-boot/efibootmgr sys-apps/util-linux

    generate_initramfs

    install_kernel

    echo "Emerging tools"
    try emerge --verbose sys-block/io-scheduler-udev-rules \
        sys-apps/mlocate dev-vcs/git net-misc/networkmanager \
        app-shells/bash-completion net-misc/chrony app-admin/sysklogd \
        sys-process/cronie sys-auth/seatd

    enable_service

    try emerge --verbose x11-drivers/xf86-video-nouveau media-libs/mesa

    echo "Set root password"
    try passwd
    einfo "script completed"
}

function configure_system() {
    einfo "Generating locales"
	echo "$LOCALES" > /etc/locale.gen \
	    || die "Could not write /etc/locale.gen"
	locale-gen \
	    || die "Could not generate locales"

    # Set hostname
	einfo "Selecting hostname"
	sed -i "/hostname=/c\\hostname=\"$HOSTNAME\"" /etc/conf.d/hostname \
		|| die "Could not sed replace in /etc/conf.d/hostname"

    # Also update /etc/hosts with the hostname
    cat >> /etc/hosts << EOF
127.0.0.1   $HOSTNAME localhost
::1         $HOSTNAME localhost
EOF

    einfo "Selecting timezone"
    einfo "timezone set to ${TIMEZONE}"
    ln -sf ../usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
	echo "$TIMEZONE" > /etc/timezone \
		|| die "Could not write /etc/timezone"
	chmod 644 /etc/timezone \
		|| die "Could not set correct permissions for /etc/timezone"
	try emerge -v --config sys-libs/timezone-data

    # Set keymap
	einfo "Selecting keymap"
	sed -i "/keymap=/c\\keymap=\"$KEYMAP\"" /etc/conf.d/keymaps \
		|| die "Could not sed replace in /etc/conf.d/keymaps"

	# Set locale
	einfo "Selecting locale"
	try eselect locale set "$LOCALE"

    env_update
}

function install_kernel() {
    echo "compile kernel"
    try emerge --oneshot --nodeps app-arch/cpio
    try emerge --verbose sys-kernel/installkernel sys-kernel/linux-firmware \
        sys-firmware/nvidia-firmware sys-firmware/sof-firmware

    try emerge --verbose sys-kernel/gentoo-sources sys-apps/pciutils \
        app-portage/gentoolkit

    echo "Selecting kernel to set 1"
    try eselect kernel set 1 \
        || die "Could not select kernel source"

    # edit_uefi-mkconfig

    cd /usr/src/linux \
        || die "could not change to /usr/linux"

    sleep 3
    zcat /proc/config.gz > .config
    make olddefconfig || die "make olddefconfig failed"
    echo "olddefconfig dubug message only"
    sleep 5

    kernel_script

    sleep 5
    make olddefconfig || die "make olddefconfig failed after scripts/config"
    sleep 5

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

    cp /usr/src/linux/arch/x86_64/boot/bzImage "/efi/EFI/Gentoo/vmlinuz-${kver}.efi" \
        || die "Could not copy bzImage to /efi/EFI/Gentoo/vmlinuz-$kver.efi"
    einfo "bzImage to /efi/EFI/Gentoo/vmlinuz-$kver.efi copied successfully"
    sleep 5

    echo "Installing kernel (triggers installkernel hooks -> ugrd -> uefi-mkconfig)"
    einfo "Deploying kernel postinst hook for USB fallback"
    mkdir -p /etc/kernel/postinst.d
    cat > /etc/kernel/postinst.d/99-usb-fallback << 'EOF'
#!/bin/bash
# Automatically update the UEFI removable-media fallback bootloader
# whenever installkernel updates the system kernel.

KVER="$1"
KERNEL_IMAGE="$2"

# installkernel passes the image path as $2, but be defensive
if [[ -z "$KERNEL_IMAGE" || ! -f "$KERNEL_IMAGE" ]]; then
    KERNEL_IMAGE="/efi/EFI/Gentoo/vmlinuz-${KVER}.efi"
    [[ -f "$KERNEL_IMAGE" ]] || KERNEL_IMAGE="/boot/vmlinuz-${KVER}"
fi

if [[ -f "$KERNEL_IMAGE" ]]; then
    mkdir -p /efi/EFI/BOOT
    cp -f "$KERNEL_IMAGE" /efi/EFI/BOOT/BOOTX64.EFI
    echo "USB fallback updated: /efi/EFI/BOOT/BOOTX64.EFI (${KVER})"
else
    echo "Warning: kernel image not found for ${KVER}, fallback not updated" >&2
fi
EOF
    chmod +x /etc/kernel/postinst.d/99-usb-fallback
    einfo "Postinst hook installed at /etc/kernel/postinst.d/99-usb-fallback"
    try make install || die "make install failed"
    sleep 10

    if [[ -f "/efi/EFI/Gentoo/vmlinuz-${kver}.efi" ]]; then
        mkdir -p /efi/EFI/BOOT
        cp -f "/efi/EFI/Gentoo/vmlinuz-${kver}.efi" /efi/EFI/BOOT/BOOTX64.EFI
        einfo "Manually updated USB fallback at /efi/EFI/BOOT/BOOTX64.EFI with embedded cmdline"
    else
        ewarn "Kernel image not found at /efi/EFI/Gentoo/vmlinuz-${kver}.efi"
    fi

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
    "ugrd.crypto.cryptsetup",
    "ugrd.crypto.gpg",
    "ugrd.fs.btrfs",
    "ugrd.fs.resume",
    "ugrd.kmod.nvme",
    "ugrd.kmod.usb"
]

mount_timeout = 5

keymap_file = "/usr/share/keymaps/i386/qwerty/sv-latin1.map.gz"
late_resume = true

auto_mounts = ['/efi']

[mounts.efi]
uuid = "$efi_uuid"
type = "vfat"

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

# function edit_uefi-mkconfig() {
#     einfo "Editing uefi-mkconfig to include cryptsetup and resume"

#     local uefi_config="/etc/default/uefi-mkconfig"
    
#     if [[ ! -f "$uefi_config" ]]; then
#         die "uefi-mkconfig config file not found at $uefi_config"
#     fi

#     # Get UUIDs from the environment or detect them
#     local root_uuid="${CHROOT_ROOT_UNDERLYING_UUID:-}"
#     local swap_uuid="${CHROOT_SWAP_UNDERLYING_UUID:-}"

#     if [[ -z "$root_uuid" || -z "$swap_uuid" ]]; then
#         ewarn "UUIDs not set in environment, using device mapper paths"
#         local kernel_cmdline="root=/dev/mapper/cryptroot rootfstype=btrfs resume=/dev/mapper/cryptswap"
#     else
#         local kernel_cmdline="root=UUID=${root_uuid} rootfstype=btrfs resume=UUID=${swap_uuid}"
#     fi

#     # Update the KERNEL_CONFIG line
#     if grep -q "^KERNEL_CONFIG=" "$uefi_config"; then
#         sed -i "s|^KERNEL_CONFIG=\".*\"|KERNEL_CONFIG=\"%entry_id %linux_name Gentoo %kernel_version ; ${kernel_cmdline}\"|" "$uefi_config" \
#             || die "Failed to update KERNEL_CONFIG in $uefi_config"
#     elif grep -q "^#KERNEL_CONFIG=" "$uefi_config"; then
#         sed -i "s|^#KERNEL_CONFIG=\".*\"|KERNEL_CONFIG=\"%entry_id %linux_name Gentoo %kernel_version ; ${kernel_cmdline}\"|" "$uefi_config" \
#             || die "Failed to uncomment and set KERNEL_CONFIG in $uefi_config"
#     else
#         echo "KERNEL_CONFIG=\"%entry_id %linux_name Gentoo %kernel_version ; ${kernel_cmdline}\"" >> "$uefi_config" \
#             || die "Failed to add KERNEL_CONFIG to $uefi_config"
#     fi

#     # Configure other settings
#     sed -i 's/^ONLY_LATEST=.*/ONLY_LATEST=false/' "$uefi_config" || die "Failed to set ONLY_LATEST"
#     sed -i 's/^REVERSE_ORDER=.*/REVERSE_ORDER=false/' "$uefi_config" || die "Failed to set REVERSE_ORDER"
#     sed -i 's/^DISABLE_LABEL_LIMIT=.*/DISABLE_LABEL_LIMIT=true/' "$uefi_config" || die "Failed to set DISABLE_LABEL_LIMIT"

#     einfo "uefi-mkconfig updated with kernel commandline: ${kernel_cmdline}"
#     einfo "DISABLE_LABEL_LIMIT set to: true"
# }

function enable_service() {
    echo "Enable services"
    try rc-service dhcpcd stop || die "rc-service dhcpcd stop failed"

    try rc-update add NetworkManager default || die "rc-update add NetworkManager default failed"
    try rc-update add chronyd default || die "rc-update add chronyd default failed"
    try rc-update add cronie default || die "rc-update add cronie default failed"
    try rc-update add seatd default || die "rc-update add seatd default failed"
    try rc-update add hostname boot || die "rc-update add hostname boot"
    try rc-update add dbus default || die "rc-update add dbus default failed"
    try rc-update add keymaps boot || die "rc-update add keymaps boot failed"

    try rc-service NetworkManager start || die "rc-service NetworkManager start failed"
}
