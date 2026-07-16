function main_install() {
    install_stage3

    mount_efivars
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

    emerge --sync --quiet
    
}

