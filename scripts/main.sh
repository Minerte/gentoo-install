set -uo pipefail

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
    sed -i "s/^#CPU_FLAGS_X86=.*/CPU_FLAGS_X86=\"${CPU_FLAGS}\"/" /etc/portage/make.conf \
        || die "could not uncomment and set CPU_FLAGS_X86"
    echo "Uncommented and set CPU_FLAGS_X86 in make.conf"
    sleep 5

    einfo "Re-emerge ALL system apps"
    try emerge --emptytree -1 @installed

    echo "merging filesystem"
    try emerge --verbose sys-fs/cryptsetup sys-fs/btrfs-progs \
        sys-fs/e2fsprogs sys-fs/dosfstools app-crypt/gnupg \
        app-arch/zstd

    env_update

    configure_uefi_mkconfig_cmdline

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

    try emerge --verbose x11-drivers/xf86-video-nouveau media-libs/mesa

    einfo "script completed"
}

function install_kernel() {
    echo "compile kernel"
    try emerge --oneshot --nodeps app-arch/cpio

    # Install efibootmgr first so uefi-mkconfig can use it
    try emerge --verbose sys-boot/efibootmgr
    try emerge --verbose sys-kernel/installkernel sys-kernel/linux-firmware sys-firmware/nvidia-firmware

    try emerge --verbose sys-kernel/gentoo-sources sys-apps/pciutils \
        sys-firmware/sof-firmware app-portage/gentoolkit

    echo "Selecting kernel to set 1"
    try eselect kernel set 1 \
        || die "Could not select kernel source"

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

    # >>> USB PORTABILITY FIX <<<
    # Copy to UEFI removable media fallback path so it boots without NVRAM entries
    mkdir -p /efi/EFI/BOOT || die "Could not create /efi/EFI/BOOT"
    cp "/efi/EFI/Gentoo/vmlinuz-${kver}.efi" /efi/EFI/BOOT/BOOTX64.EFI \
        || die "Could not copy kernel to fallback BOOTX64.EFI"
    einfo "Fallback bootloader installed at /efi/EFI/BOOT/BOOTX64.EFI"
    # >>> END FIX <<<
    sleep 5

    echo "Installing kernel (triggers installkernel hooks -> ugrd -> uefi-mkconfig)"
    # >>> FUTURE-PROOF: Auto-update fallback on every kernel install <<<
    einfo "Deploying kernel postinst hook for USB fallback"
    mkdir -p /etc/kernel/postinst.d
    cat > /etc/kernel/postinst.d/99-usb-fallback << 'EOF'
#!/bin/bash
# Automatically update the UEFI removable-media fallback bootloader
# whenever installkernel updates the system kernel.
KVER="$1"
KERNEL_IMAGE="$2"

# installkernel passes the image path as $2, but be defensive
if [[ -z "$KERNEL_IMAGE" ]] || [[ ! -f "$KERNEL_IMAGE" ]]; then
    KERNEL_IMAGE="/efi/EFI/Gentoo/vmlinuz-${KVER}.efi"
    [[ -f "$KERNEL_IMAGE" ]] || KERNEL_IMAGE="/boot/vmlinuz-${KVER}"
fi

if [[ -f "$KERNEL_IMAGE" ]]; then
    mkdir -p /efi/EFI/BOOT
    cp -f "$KERNEL_IMAGE" /efi/EFI/BOOT/BOOTX64.EFI
    echo "USB fallback updated: /efi/EFI/BOOT/BOOTX64.EFI ($KVER)"
else
    echo "Warning: kernel image not found for $KVER, fallback not updated" >&2
fi
EOF
    chmod +x /etc/kernel/postinst.d/99-usb-fallback
    einfo "Postinst hook installed at /etc/kernel/postinst.d/99-usb-fallback"
    # >>> END FUTURE-PROOF <<<
    try make install || die "make install failed"
    sleep 10

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
    "ugrd.fs.btrfs",
    "ugrd.fs.resume"
]

keymap_file = "/usr/share/keymaps/i386/qwerty/sv-latin1.map.gz"
late_resume = true

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

function configure_uefi_mkconfig_cmdline() {
    einfo "Configuring /etc/default/uefi-mkconfig"

    local ROOT_UUID="${ROOT_UUID:-${CHROOT_ROOT_UUID:-}}"
    local CRYPTROOT_UUID="${CRYPTROOT_UUID:-${CHROOT_ROOT_UNDERLYING_UUID:-}}"
    local SWAP_UUID="${SWAP_UUID:-${CHROOT_SWAP_UUID:-}}"

    local ROOT_LUKS_UUID="${CHROOT_ROOT_UNDERLYING_UUID:-}"
    local SWAP_LUKS_UUID="${CHROOT_SWAP_UNDERLYING_UUID:-}"

    [[ -n "$ROOT_UUID" ]] \
        || die "ROOT_UUID/CHROOT_ROOT_UUID is empty"

    [[ -n "$CRYPTROOT_UUID" ]] \
        || die "CRYPTROOT_UUID/CHROOT_ROOT_UNDERLYING_UUID is empty"

    [[ -n "$SWAP_UUID" ]] \
        || die "SWAP_UUID/CHROOT_SWAP_UUID is empty"

    if [[ "$ROOT_UUID" == "$ROOT_LUKS_UUID" ]]; then
        die "root=UUID must use CHROOT_ROOT_UUID, not CHROOT_ROOT_UNDERLYING_UUID"
    fi

    if [[ "$SWAP_UUID" == "$SWAP_LUKS_UUID" ]]; then
        die "resume=UUID must use CHROOT_SWAP_UUID, not CHROOT_SWAP_UNDERLYING_UUID"
    fi

    # Detect Btrfs subvolume, fallback to activeroot
    local root_subvol="activeroot"
    local root_opts
    local detected_subvol

    root_opts=$(awk '$2 == "/" {print $4; exit}' /proc/mounts 2>/dev/null || true)

    if [[ -n "$root_opts" ]]; then
        detected_subvol=$(printf '%s\n' "$root_opts" \
            | grep -o 'subvol=[^,]*' \
            | head -n1 \
            | cut -d= -f2- \
            || true)

        detected_subvol=${detected_subvol#/}

        [[ -n "$detected_subvol" ]] && root_subvol="$detected_subvol"
    fi

    local cmdline="root=UUID=${ROOT_UUID} rootflags=subvol=${root_subvol} rd.luks.uuid=${CRYPTROOT_UUID} ro resume=UUID=${SWAP_UUID}"

    einfo "Target kernel cmdline:"
    echo "$cmdline"

    # Still useful for other tools
    printf '%s\n' "$cmdline" > /etc/kernel/cmdline

    local default_file="/etc/default/uefi-mkconfig"
    local new_line

    new_line=$(printf 'KERNEL_CONFIG="%%entry_id %%linux_name Linux %%kernel_version ; %s"' "$cmdline")

    if [[ -f "$default_file" ]]; then
        cp "$default_file" "${default_file}.bak" \
            || ewarn "Could not back up $default_file"
    fi

    mkdir -p "$(dirname "$default_file")"

    if [[ -f "$default_file" ]] && grep -q '^KERNEL_CONFIG=' "$default_file"; then
        NEW_LINE="$new_line" awk '
            /^KERNEL_CONFIG=/ {
                print ENVIRON["NEW_LINE"]
                next
            }
            { print }
        ' "$default_file" > "${default_file}.tmp" \
            || die "Could not rewrite $default_file"

        mv "${default_file}.tmp" "$default_file" \
            || die "Could not replace $default_file"
    else
        printf '%s\n' "$new_line" >> "$default_file" \
            || die "Could not write $default_file"
    fi

    einfo "Updated $default_file:"
    cat "$default_file"
}

function enable_service() {
    echo "Enable services"
    try rc-service dhcpcd stop || die "rc-service dhcpcd stop failed"

    try rc-update add NetworkManager default || die "rc-update add NetworkManager default failed"
    try rc-update add chronyd default || die "rc-update add chronyd default failed"
    try rc-update add cronie default || die "rc-update add cronie default failed"
    try rc-update add seatd default || die "rc-updtae add seatd default failed"
    try rc-update add hostname boot || die "rc-update add hostname boot"
    try rc-update add dbus default || die "rc-update add dbus default failed"
    try rc-update add keymaps boot || die "rc-update add keymaps boot failed"

    try rc-service NetworkManager start || die "rc-service NetworkManager start failed"
}
