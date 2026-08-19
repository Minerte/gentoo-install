function kernel_script() {
	einfo "running ./scripts/config"
	# =============================================================================
	# Gentoo Kernel Configuration Script
	# =============================================================================
	# Hardware:
	#   Motherboard : ASUS ROG X670E Gene
	#   CPU         : AMD Ryzen 9 9950X
	#   RAM         : 96GB
	#   GPU         : ASUS RTX 3090 (nouveau)
	#   Storage     : 1x NVMe + 3x SATA SSD
	#
	# Use-case:
	#   - BTRFS root filesystem
	#   - Separate /efi partition
	#   - ugrd initramfs with GPG-encrypted LUKS key
	#   - KVM/QEMU virtualization (many VMs)
	#   - VFIO GPU passthrough
	#   - Kernel version: 6.18.41 (gentoo-sources)
	# =============================================================================

	# =============================================================================
	# 1. CRITICAL: Initramfs / Initrd Support (ugrd)
	# Without these, the kernel cannot load ugrd at all.
	# =============================================================================
	try ./scripts/config --enable CONFIG_BLK_DEV_INITRD || die "module do not exit CONFIG_BLK_DEV_INITRD"
	try ./scripts/config --enable CONFIG_BLK_DEV_RAM || die "module do not exit CONFIG_BLK_DEV_RAM"
	try ./scripts/config --enable CONFIG_RD_ZSTD || die "module do not exit CONFIG_RD_ZSTD"

	# =============================================================================
	# 2. Module Support (ugrd uses kmod for auto-loading)
	# =============================================================================
	try ./scripts/config --enable CONFIG_MODULES || die "module do not exit CONFIG_MODULES"
	try ./scripts/config --enable CONFIG_MODULE_UNLOAD || die "module do not exit CONFIG_MODULE_UNLOAD"
	try ./scripts/config --enable CONFIG_MODVERSIONS || die "module do not exit CONFIG_MODVERSIONS"
	try ./scripts/config --enable CONFIG_KALLSYMS || die "module do not exit CONFIG_KALLSYMS"
	try ./scripts/config --enable CONFIG_KALLSYMS_ALL || die "module do not exit CONFIG_KALLSYMS_ALL"

	# =============================================================================
	# 3. BTRFS Filesystem
	# =============================================================================
	try ./scripts/config --enable CONFIG_BTRFS_FS || die "module do not exit CONFIG_BTRFS_FS"
	try ./scripts/config --enable CONFIG_BTRFS_FS_POSIX_ACL || die "module do not exit CONFIG_BTRFS_FS_POSIX_ACL"
	try ./scripts/config --enable CONFIG_BTRFS_FS_CHECK_INTEGRITY || die "module do not exit CONFIG_BTRFS_FS_CHECK_INTEGRITY"
	try ./scripts/config --enable CONFIG_BTRFS_FS_COMPRESS || die "module do not exit CONFIG_BTRFS_FS_COMPRESS"

	# =============================================================================
	# 4. ZSTD Compression (for BTRFS and initrd)
	# =============================================================================
	try ./scripts/config --enable CONFIG_ZSTD_COMPRESS || die "module do not exit CONFIG_ZSTD_COMPRESS"
	try ./scripts/config --enable CONFIG_ZSTD_DECOMPRESS || die "module do not exit CONFIG_ZSTD_DECOMPRESS"

	# =============================================================================
	# 5. Cryptography: dm-crypt + GPG key decryption
	# =============================================================================
	# Core device-mapper crypto
	try ./scripts/config --enable CONFIG_DM_CRYPT || die "module do not exit CONFIG_DM_CRYPT"
	try ./scripts/config --enable CONFIG_MD || die "module do not exit CONFIG_MD"
	try ./scripts/config --enable CONFIG_BLK_DEV_DM || die "module do not exit CONFIG_BLK_DEV_DM"
	try ./scripts/config --enable CONFIG_DM_INIT || die "module do not exit CONFIG_DM_INIT"
	try ./scripts/config --enable CONFIG_DM_INTEGRITY || die "module do not exit CONFIG_DM_INTEGRITY"

	# Crypto API manager
	try ./scripts/config --enable CONFIG_CRYPTO_MANAGER || die "module do not exit CONFIG_CRYPTO_MANAGER"
	try ./scripts/config --enable CONFIG_CRYPTO_USER_API || die "module do not exit CONFIG_CRYPTO_USER_API"
	try ./scripts/config --enable CONFIG_CRYPTO_USER_API_HASH || die "module do not exit CONFIG_CRYPTO_USER_API_HASH"
	try ./scripts/config --enable CONFIG_CRYPTO_USER_API_SKCIPHER || die "module do not exit CONFIG_CRYPTO_USER_API_SKCIPHER"

	# Core ciphers and hashes for LUKS
	try ./scripts/config --enable CONFIG_CRYPTO_AES || die "module do not exit CONFIG_CRYPTO_AES"
	try ./scripts/config --enable CONFIG_CRYPTO_XTS || die "module do not exit CONFIG_CRYPTO_XTS"
	try ./scripts/config --enable CONFIG_CRYPTO_SHA256 || die "module do not exit CONFIG_CRYPTO_SHA256"
	try ./scripts/config --enable CONFIG_CRYPTO_SHA512 || die "module do not exit CONFIG_CRYPTO_SHA512"
	try ./scripts/config --enable CONFIG_CRYPTO_CRC32C || die "module do not exit CONFIG_CRYPTO_CRC32C"
	try ./scripts/config --enable CONFIG_CRYPTO_XXHASH || die "module do not exit CONFIG_CRYPTO_XXHASH"

	# Intel CRC32C optimization
	try ./scripts/config --enable CONFIG_CRC32C_INTEL || die "module do not exit CONFIG_CRC32C_INTEL"

	# RNG / DRBG
	try ./scripts/config --enable CONFIG_CRYPTO_DRBG || die "module do not exit CONFIG_CRYPTO_DRBG"
	try ./scripts/config --enable CONFIG_CRYPTO_JITTERENTROPY || die "module do not exit CONFIG_CRYPTO_JITTERENTROPY"
	try ./scripts/config --enable CONFIG_CRYPTO_RNG_DEFAULT || die "module do not exit CONFIG_CRYPTO_RNG_DEFAULT"

	# Additional algorithms required for GPG decryption
	try ./scripts/config --enable CONFIG_CRYPTO_GCM || die "module do not exit CONFIG_CRYPTO_GCM"
	try ./scripts/config --enable CONFIG_CRYPTO_CBC || die "module do not exit CONFIG_CRYPTO_CBC"
	try ./scripts/config --enable CONFIG_CRYPTO_ECB || die "module do not exit CONFIG_CRYPTO_ECB"
	try ./scripts/config --enable CONFIG_CRYPTO_HMAC || die "module do not exit CONFIG_CRYPTO_HMAC"
	try ./scripts/config --enable CONFIG_CRYPTO_AEAD || die "module do not exit CONFIG_CRYPTO_AEAD"
	try ./scripts/config --enable CONFIG_CRYPTO_SEQIV || die "module do not exit CONFIG_CRYPTO_SEQIV"

	# GPG public-key algorithms (RSA + ECC for smartcards/YubiKey)
	try ./scripts/config --enable CONFIG_CRYPTO_RSA || die "module do not exit CONFIG_CRYPTO_RSA"
	try ./scripts/config --enable CONFIG_CRYPTO_ECC || die "module do not exit CONFIG_CRYPTO_ECC"
	try ./scripts/config --enable CONFIG_CRYPTO_ECDH || die "module do not exit CONFIG_CRYPTO_ECDH"
	try ./scripts/config --enable CONFIG_CRYPTO_ECDSA || die "module do not exit CONFIG_CRYPTO_ECDSA"

	# =============================================================================
	# 6. NVMe (1x NVMe disk - core built-in, fabrics as modules)
	# =============================================================================
	try ./scripts/config --enable CONFIG_NVME_CORE || die "module do not exit CONFIG_NVME_CORE"
	try ./scripts/config --enable CONFIG_BLK_DEV_NVME || die "module do not exit CONFIG_BLK_DEV_NVME"
	try ./scripts/config --module CONFIG_NVME_FABRICS || die "module do not exit CONFIG_NVME_FABRICS"
	try ./scripts/config --module CONFIG_NVME_FC || die "module do not exit CONFIG_NVME_FC"
	try ./scripts/config --module CONFIG_NVME_TCP || die "module do not exit CONFIG_NVME_TCP"
	try ./scripts/config --module CONFIG_NVME_KEYRING || die "module do not exit CONFIG_NVME_KEYRING"
	try ./scripts/config --enable CONFIG_NVME_AUTH || die "module do not exit CONFIG_NVME_AUTH"
	try ./scripts/config --module CONFIG_NVME_TARGET || die "module do not exit CONFIG_NVME_TARGET"
	try ./scripts/config --module CONFIG_NVME_TARGET_LOOP || die "module do not exit CONFIG_NVME_TARGET_LOOP"
	try ./scripts/config --module CONFIG_NVME_TARGET_FC || die "module do not exit CONFIG_NVME_TARGET_FC"
	try ./scripts/config --module CONFIG_NVME_TARGET_TCP || die "module do not exit CONFIG_NVME_TARGET_TCP"
	try ./scripts/config --enable CONFIG_NVME_TARGET_AUTH || die "module do not exit CONFIG_NVME_TARGET_AUTH"

	# =============================================================================
	# 7. SATA / SCSI (3x SSD)
	# =============================================================================
	try ./scripts/config --enable CONFIG_ATA || die "module do not exit CONFIG_ATA"
	try ./scripts/config --enable CONFIG_SATA_AHCI || die "module do not exit CONFIG_SATA_AHCI"
	try ./scripts/config --enable CONFIG_SATA_AHCI_PLATFORM || die "module do not exit CONFIG_SATA_AHCI_PLATFORM"
	try ./scripts/config --enable CONFIG_SCSI || die "module do not exit CONFIG_SCSI"
	try ./scripts/config --enable CONFIG_BLK_DEV_SD || die "module do not exit CONFIG_BLK_DEV_SD"
	# Additional storage controllers for AMD X670E
	try ./scripts/config --enable CONFIG_SATA_HIGHBANK || die "module do not exit CONFIG_SATA_HIGHBANK"
	try ./scripts/config --enable CONFIG_SATA_ACARD_AHCI || die "module do not exit CONFIG_SATA_ACARD_AHCI"
	try ./scripts/config --enable CONFIG_PATA_AMD || die "module do not exit CONFIG_PATA_AMD"

	# =============================================================================
	# 8. DAX (Direct Access) support
	# =============================================================================
	try ./scripts/config --enable CONFIG_DAX || die "module do not exit CONFIG_DAX"

	# =============================================================================
	# 9. EFI Support (separate /efi partition)
	# =============================================================================
	try ./scripts/config --enable CONFIG_EFI || die "module do not exit CONFIG_EFI"
	try ./scripts/config --enable CONFIG_EFIVAR_FS || die "module do not exit CONFIG_EFIVAR_FS"
	try ./scripts/config --enable CONFIG_EFI_PARTITION || die "module do not exit CONFIG_EFI_PARTITION"
	try ./scripts/config --enable CONFIG_EFI_RUNTIME_MAP || die "module do not exit CONFIG_EFI_RUNTIME_MAP"
	try ./scripts/config --enable CONFIG_EFI_STUB || die "module do not exit CONFIG_EFI_STUB"
	try ./scripts/config --enable CONFIG_EFI_VARS || die "module do not exit CONFIG_EFI_VARS"
	try ./scripts/config --enable CONFIG_PROC_FS || die "module do not exit CONFIG_PROC_FS"

	# =============================================================================
	# 10. Framebuffer / DRM / Nouveau for RTX 3090
	# =============================================================================
	# Use nouveau, not the proprietary NVIDIA driver.
	#
	# For your ugrd + GPG LUKS setup, the early passphrase prompt can usually use
	# EFI framebuffer / simpledrm. Nouveau can then load after the real root is
	# available.
	#
	# Recommended: CONFIG_DRM_NOUVEAU=m
	#
	# If you specifically need nouveau active inside the initramfs, you can build
	# it built-in with CONFIG_DRM_NOUVEAU=y, but then GPU firmware must also be
	# available very early, either in the initramfs or through CONFIG_EXTRA_FIRMWARE.
	# For an encrypted root, module mode is usually simpler.
	# =============================================================================

	# Early boot framebuffer/console support.
	try ./scripts/config --enable CONFIG_FB || die "Failed to set CONFIG_FB"
	try ./scripts/config --enable CONFIG_FB_EFI || die "Failed to set CONFIG_FB_EFI"
	try ./scripts/config --enable CONFIG_DRM_SIMPLEDRM || die "Failed to set CONFIG_DRM_SIMPLEDRM"
	try ./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE || die "Failed to set CONFIG_FRAMEBUFFER_CONSOLE"
	try ./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY || die "Failed to set CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY"

	# DRM core support.
	try ./scripts/config --enable CONFIG_DRM || die "Failed to set CONFIG_DRM"
	try ./scripts/config --enable CONFIG_DRM_KMS_HELPER || die "Failed to set CONFIG_DRM_KMS_HELPER"
	try ./scripts/config --enable CONFIG_DRM_FBDEV_EMULATION || die "Failed to set CONFIG_DRM_FBDEV_EMULATION"

	# DRM helpers used by nouveau.
	try ./scripts/config --enable CONFIG_DRM_TTM || die "Failed to set CONFIG_DRM_TTM"
	try ./scripts/config --enable CONFIG_DRM_TTM_HELPER || die "Failed to set CONFIG_DRM_TTM_HELPER"
	try ./scripts/config --enable CONFIG_DRM_EXEC || die "Failed to set CONFIG_DRM_EXEC"
	try ./scripts/config --enable CONFIG_DRM_SCHED || die "Failed to set CONFIG_DRM_SCHED"

	# Nouveau driver.
	#
	# Recommended for your setup:
	# try ./scripts/config --module CONFIG_DRM_NOUVEAU || die "Failed to set CONFIG_DRM_NOUVEAU=m"

	# Alternative, only if you need nouveau inside initramfs:
	try ./scripts/config --enable CONFIG_DRM_NOUVEAU || die "Failed to set CONFIG_DRM_NOUVEAU=y"

	# Remove this line from your script; it is probably not a useful/current Kconfig symbol:
	try ./scripts/config --enable CONFIG_NOUVEAU_DEBUG_DEFAULT

	# =============================================================================
	# 11. Console / TTY / VT
	# =============================================================================
	try ./scripts/config --enable CONFIG_VT || die "module do not exit CONFIG_VT"
	try ./scripts/config --enable CONFIG_VT_HW_CONSOLE_BINDING || die "module do not exit CONFIG_VT_HW_CONSOLE_BINDING"
	try ./scripts/config --enable CONFIG_UNIX98_PTYS || die "module do not exit CONFIG_UNIX98_PTYS"
	try ./scripts/config --enable CONFIG_TTY || die "module do not exit CONFIG_TTY"

	# =============================================================================
	# 12. USB Host Controllers (built-in for ugrd)
	# =============================================================================
	try ./scripts/config --enable CONFIG_USB_SUPPORT || die "module do not exit CONFIG_USB_SUPPORT"
	try ./scripts/config --enable CONFIG_USB_XHCI_HCD || die "module do not exit CONFIG_USB_XHCI_HCD"
	try ./scripts/config --enable CONFIG_USB_EHCI_HCD || die "module do not exit CONFIG_USB_EHCI_HCD"
	try ./scripts/config --enable CONFIG_USB_OHCI_HCD || die "module do not exit CONFIG_USB_OHCI_HCD"
	try ./scripts/config --enable CONFIG_USB_UHCI_HCD || die "module do not exit CONFIG_USB_UHCI_HCD"
	try ./scripts/config --enable CONFIG_USB_UAS || die "module do not exit CONFIG_USB_UAS"

	# =============================================================================
	# 13. USB Storage (if GPG keyfile is on USB)
	# =============================================================================
	try ./scripts/config --enable CONFIG_USB_STORAGE || die "module do not exit CONFIG_USB_STORAGE"
	try ./scripts/config --enable CONFIG_USB_STORAGE_UAS || die "module do not exit CONFIG_USB_STORAGE_UAS"
	try ./scripts/config --enable CONFIG_UAS || die "module do not exit CONFIG_UAS"

	# =============================================================================
	# 14. HID / Input (keyboard for typing GPG passphrase in initramfs)
	# =============================================================================
	try ./scripts/config --enable CONFIG_HID || die "module do not exit CONFIG_HID"
	try ./scripts/config --enable CONFIG_HID_GENERIC || die "module do not exit CONFIG_HID_GENERIC"
	try ./scripts/config --enable CONFIG_USB_HID || die "module do not exit CONFIG_USB_HID"
	try ./scripts/config --enable CONFIG_INPUT || die "module do not exit CONFIG_INPUT"
	try ./scripts/config --enable CONFIG_INPUT_EVDEV || die "module do not exit CONFIG_INPUT_EVDEV"
	try ./scripts/config --enable CONFIG_INPUT_KEYBOARD || die "module do not exit CONFIG_INPUT_KEYBOARD"
	try ./scripts/config --enable CONFIG_INPUT_MOUSE || die "module do not exit CONFIG_INPUT_MOUSE"

	# =============================================================================
	# 15. FAT / VFAT (for /efi partition)
	# =============================================================================
	try ./scripts/config --enable CONFIG_FAT_FS || die "module do not exit CONFIG_FAT_FS"
	try ./scripts/config --enable CONFIG_VFAT_FS || die "module do not exit CONFIG_VFAT_FS"
	try ./scripts/config --enable CONFIG_NLS_CODEPAGE_437 || die "module do not exit CONFIG_NLS_CODEPAGE_437"
	try ./scripts/config --enable CONFIG_NLS_ISO8859_1 || die "module do not exit CONFIG_NLS_ISO8859_1"

	# =============================================================================
	# 16. AMD Platform: Ryzen 9 9950X + X670E Gene
	# =============================================================================
	try ./scripts/config --enable CONFIG_AMD_NB || die "module do not exit CONFIG_AMD_NB"
	try ./scripts/config --enable CONFIG_X86_AMD_PLATFORM_DEVICE || die "module do not exit CONFIG_X86_AMD_PLATFORM_DEVICE"
	try ./scripts/config --enable CONFIG_AMD_PMC || die "module do not exit CONFIG_AMD_PMC"

	# AMD P-State driver (preferred for Zen 4/5)
	try ./scripts/config --enable CONFIG_AMD_PSTATE || die "module do not exit CONFIG_AMD_PSTATE"
	try ./scripts/config --enable CONFIG_AMD_PSTATE_UT || die "module do not exit CONFIG_AMD_PSTATE_UT"
	try ./scripts/config --enable CONFIG_X86_AMD_PSTATE || die "module do not exit CONFIG_X86_AMD_PSTATE"

	# CPU temperature monitoring
	try ./scripts/config --enable CONFIG_SENSORS_K10TEMP || die "module do not exit CONFIG_SENSORS_K10TEMP"

	# IOMMU (critical for X670E chipset and VFIO passthrough)
	try ./scripts/config --enable CONFIG_AMD_IOMMU || die "module do not exit CONFIG_AMD_IOMMU"
	try ./scripts/config --enable CONFIG_AMD_IOMMU_V2 || die "module do not exit CONFIG_AMD_IOMMU_V2"
	try ./scripts/config --enable CONFIG_IOMMU_SUPPORT || die "module do not exit CONFIG_IOMMU_SUPPORT"
	try ./scripts/config --enable CONFIG_IOMMU_DMA || die "module do not exit CONFIG_IOMMU_DMA"

	# EDAC (if using ECC memory)
	try ./scripts/config --enable CONFIG_EDAC || die "module do not exit CONFIG_EDAC"
	try ./scripts/config --enable CONFIG_EDAC_AMD64 || die "module do not exit CONFIG_EDAC_AMD64"

	# AMD SoC features (audio, SMBus, etc. common on X670E)
	try ./scripts/config --enable CONFIG_AMD_SFH_HID || die "module do not exit CONFIG_AMD_SFH_HID"
	try ./scripts/config --enable CONFIG_AMD_PMF || die "module do not exit CONFIG_AMD_PMF"

	# =============================================================================
	# 17. Sound (PipeWire)
	# =============================================================================
	try ./scripts/config --enable CONFIG_SOUND || die "module do not exit CONFIG_SOUND"
	try ./scripts/config --enable CONFIG_SND || die "module do not exit CONFIG_SND"
	try ./scripts/config --enable CONFIG_SND_PROC_FS || die "module do not exit CONFIG_SND_PROC_FS"
	try ./scripts/config --enable CONFIG_SND_VERBOSE_PROCFS || die "module do not exit CONFIG_SND_VERBOSE_PROCFS"

	# =============================================================================
	# 18. KVM / QEMU Virtualization (many VMs)
	# =============================================================================
	# Core KVM support
	try ./scripts/config --enable CONFIG_KVM || die "module do not exit CONFIG_KVM"
	try ./scripts/config --enable CONFIG_KVM_AMD || die "module do not exit CONFIG_KVM_AMD"
	try ./scripts/config --enable CONFIG_KVM_AMD_SEV || die "module do not exit CONFIG_KVM_AMD_SEV"
	try ./scripts/config --enable CONFIG_KVM_VFIO || die "module do not exit CONFIG_KVM_VFIO"
	try ./scripts/config --enable CONFIG_KVM_GENERIC_DIRTYLOG_READ_PROTECT || die "module do not exit CONFIG_KVM_GENERIC_DIRTYLOG_READ_PROTECT"
	try ./scripts/config --enable CONFIG_KVM_COMPAT || die "module do not exit CONFIG_KVM_COMPAT"
	try ./scripts/config --enable CONFIG_KVM_ASYNC_PF || die "module do not exit CONFIG_KVM_ASYNC_PF"
	try ./scripts/config --enable CONFIG_KVM_MMIO || die "module do not exit CONFIG_KVM_MMIO"
	try ./scripts/config --enable CONFIG_KVM_SW_PROTECTED_VM || die "module do not exit CONFIG_KVM_SW_PROTECTED_VM"
	try ./scripts/config --enable CONFIG_KVM_XFER_TO_GUEST_WORK || die "module do not exit CONFIG_KVM_XFER_TO_GUEST_WORK"

	# KVM prerequisites (auto-selected by above, but explicit is safer)
	try ./scripts/config --enable CONFIG_HAVE_KVM || die "module do not exit CONFIG_HAVE_KVM"
	try ./scripts/config --enable CONFIG_HAVE_KVM_IRQCHIP || die "module do not exit CONFIG_HAVE_KVM_IRQCHIP"
	try ./scripts/config --enable CONFIG_HAVE_KVM_IRQFD || die "module do not exit CONFIG_HAVE_KVM_IRQFD"
	try ./scripts/config --enable CONFIG_HAVE_KVM_IRQ_ROUTING || die "module do not exit CONFIG_HAVE_KVM_IRQ_ROUTING"
	try ./scripts/config --enable CONFIG_HAVE_KVM_EVENTFD || die "module do not exit CONFIG_HAVE_KVM_EVENTFD"
	try ./scripts/config --enable CONFIG_HAVE_KVM_MSI || die "module do not exit CONFIG_HAVE_KVM_MSI"
	try ./scripts/config --enable CONFIG_HAVE_KVM_CPU_RELAX_INTERCEPT || die "module do not exit CONFIG_HAVE_KVM_CPU_RELAX_INTERCEPT"
	try ./scripts/config --enable CONFIG_HAVE_KVM_IRQ_BYPASS || die "module do not exit CONFIG_HAVE_KVM_IRQ_BYPASS"
	try ./scripts/config --enable CONFIG_HAVE_KVM_NO_POLL || die "module do not exit CONFIG_HAVE_KVM_NO_POLL"

	# Nested virtualization is enabled via module parameter:
	#   echo "options kvm_amd nested=1" > /etc/modprobe.d/kvm.conf

	# =============================================================================
	# 19. VFIO / GPU Passthrough (RTX 3090)
	# =============================================================================
	# Core VFIO
	try ./scripts/config --enable CONFIG_VFIO || die "module do not exit CONFIG_VFIO"
	try ./scripts/config --enable CONFIG_VFIO_PCI || die "module do not exit CONFIG_VFIO_PCI"
	try ./scripts/config --enable CONFIG_VFIO_PCI_VGA || die "module do not exit CONFIG_VFIO_PCI_VGA"
	try ./scripts/config --enable CONFIG_VFIO_PCI_MMAP || die "module do not exit CONFIG_VFIO_PCI_MMAP"
	try ./scripts/config --enable CONFIG_VFIO_PCI_INTX || die "module do not exit CONFIG_VFIO_PCI_INTX"
	try ./scripts/config --enable CONFIG_VFIO_IOMMU_TYPE1 || die "module do not exit CONFIG_VFIO_IOMMU_TYPE1"
	try ./scripts/config --enable CONFIG_VFIO_VIRQFD || die "module do not exit CONFIG_VFIO_VIRQFD"
	try ./scripts/config --enable CONFIG_VFIO_NOIOMMU || die "module do not exit CONFIG_VFIO_NOIOMMU"

	# Mediated devices (for vGPU / Intel GVT-g / NVIDIA vGPU if ever needed)
	try ./scripts/config --enable CONFIG_VFIO_MDEV || die "module do not exit CONFIG_VFIO_MDEV"
	try ./scripts/config --enable CONFIG_VFIO_MDEV_DEVICE || die "module do not exit CONFIG_VFIO_MDEV_DEVICE"

	# IOMMU user-space API (new in 6.6+, used by modern QEMU)
	try ./scripts/config --enable CONFIG_IOMMUFD || die "module do not exit CONFIG_IOMMUFD"

	# IRQ remapping (required for IOMMU)
	try ./scripts/config --enable CONFIG_IRQ_REMAP || die "module do not exit CONFIG_IRQ_REMAP"

	# PCI stub driver (for manually binding devices before vfio-pci)
	try ./scripts/config --enable CONFIG_PCI_STUB || die "module do not exit CONFIG_PCI_STUB"

	# =============================================================================
	# 20. VirtIO (paravirtualized drivers for guests)
	# =============================================================================
	# Core virtio
	try ./scripts/config --enable CONFIG_VIRTIO || die "module do not exit CONFIG_VIRTIO"
	try ./scripts/config --enable CONFIG_VIRTIO_MENU || die "module do not exit CONFIG_VIRTIO_MENU"
	try ./scripts/config --enable CONFIG_VIRTIO_PCI_LIB || die "module do not exit CONFIG_VIRTIO_PCI_LIB"
	try ./scripts/config --enable CONFIG_VIRTIO_PCI_LIB_LEGACY || die "module do not exit CONFIG_VIRTIO_PCI_LIB_LEGACY"
	try ./scripts/config --enable CONFIG_VIRTIO_ANCHOR || die "module do not exit CONFIG_VIRTIO_ANCHOR"

	# VirtIO PCI transport
	try ./scripts/config --enable CONFIG_VIRTIO_PCI || die "module do not exit CONFIG_VIRTIO_PCI"
	try ./scripts/config --enable CONFIG_VIRTIO_PCI_LEGACY || die "module do not exit CONFIG_VIRTIO_PCI_LEGACY"

	# VirtIO block / net / console / balloon / input / mem
	try ./scripts/config --enable CONFIG_VIRTIO_BLK || die "module do not exit CONFIG_VIRTIO_BLK"
	try ./scripts/config --enable CONFIG_VIRTIO_NET || die "module do not exit CONFIG_VIRTIO_NET"
	try ./scripts/config --enable CONFIG_VIRTIO_CONSOLE || die "module do not exit CONFIG_VIRTIO_CONSOLE"
	try ./scripts/config --enable CONFIG_VIRTIO_BALLOON || die "module do not exit CONFIG_VIRTIO_BALLOON"
	try ./scripts/config --enable CONFIG_VIRTIO_INPUT || die "module do not exit CONFIG_VIRTIO_INPUT"
	try ./scripts/config --enable CONFIG_VIRTIO_MEM || die "module do not exit CONFIG_VIRTIO_MEM"

	# VirtIO MMIO (for microVMs / Firecracker)
	try ./scripts/config --enable CONFIG_VIRTIO_MMIO || die "module do not exit CONFIG_VIRTIO_MMIO"
	try ./scripts/config --enable CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES || die "module do not exit CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES"

	# VirtIO filesystem (virtiofs)
	try ./scripts/config --enable CONFIG_VIRTIO_FS || die "module do not exit CONFIG_VIRTIO_FS"

	# VirtIO IOMMU (paravirtualized IOMMU for guests)
	try ./scripts/config --enable CONFIG_VIRTIO_IOMMU || die "module do not exit CONFIG_VIRTIO_IOMMU"

	# VirtIO vsockets
	try ./scripts/config --enable CONFIG_VIRTIO_VSOCKETS || die "module do not exit CONFIG_VIRTIO_VSOCKETS"
	try ./scripts/config --enable CONFIG_VIRTIO_VSOCKETS_COMMON || die "module do not exit CONFIG_VIRTIO_VSOCKETS_COMMON"

	# VirtIO SCSI
	try ./scripts/config --enable CONFIG_SCSI_VIRTIO || die "module do not exit CONFIG_SCSI_VIRTIO"

	# Block MQ virtio support
	try ./scripts/config --enable CONFIG_BLK_MQ_VIRTIO || die "module do not exit CONFIG_BLK_MQ_VIRTIO"

	# HW random virtio
	try ./scripts/config --enable CONFIG_HW_RANDOM_VIRTIO || die "module do not exit CONFIG_HW_RANDOM_VIRTIO"

	# =============================================================================
	# 21. vhost (host-side acceleration for VirtIO)
	# =============================================================================
	try ./scripts/config --enable CONFIG_VHOST_NET || die "module do not exit CONFIG_VHOST_NET"
	try ./scripts/config --enable CONFIG_VHOST_VSOCK || die "module do not exit CONFIG_VHOST_VSOCK"
	try ./scripts/config --enable CONFIG_VHOST_TASKLET || die "module do not exit CONFIG_VHOST_TASKLET"
	try ./scripts/config --enable CONFIG_VHOST_CROSS_ENDIAN || die "module do not exit CONFIG_VHOST_CROSS_ENDIAN"

	# =============================================================================
	# 22. VM Networking (bridges, taps, veth, macvlan)
	# =============================================================================
	try ./scripts/config --enable CONFIG_NET || die "module do not exit CONFIG_NET"
	try ./scripts/config --enable CONFIG_INET || die "module do not exit CONFIG_INET"
	try ./scripts/config --enable CONFIG_NETFILTER || die "module do not exit CONFIG_NETFILTER"
	try ./scripts/config --enable CONFIG_NET_CORE || die "module do not exit CONFIG_NET_CORE"
	try ./scripts/config --enable CONFIG_BRIDGE || die "module do not exit CONFIG_BRIDGE"
	try ./scripts/config --enable CONFIG_BRIDGE_NETFILTER || die "module do not exit CONFIG_BRIDGE_NETFILTER"
	try ./scripts/config --enable CONFIG_VETH || die "module do not exit CONFIG_VETH"
	try ./scripts/config --enable CONFIG_MACVLAN || die "module do not exit CONFIG_MACVLAN"
	try ./scripts/config --enable CONFIG_MACVTAP || die "module do not exit CONFIG_MACVTAP"
	try ./scripts/config --enable CONFIG_TUN || die "module do not exit CONFIG_TUN"
	try ./scripts/config --enable CONFIG_TAP || die "module do not exit CONFIG_TAP"

	# =============================================================================
	# 23. 9P / FUSE (file sharing between host and guests)
	# =============================================================================
	try ./scripts/config --enable CONFIG_NET_9P || die "module do not exit CONFIG_NET_9P"
	try ./scripts/config --enable CONFIG_NET_9P_VIRTIO || die "module do not exit CONFIG_NET_9P_VIRTIO"
	try ./scripts/config --enable CONFIG_9P_FS || die "module do not exit CONFIG_9P_FS"
	try ./scripts/config --enable CONFIG_9P_FS_POSIX_ACL || die "module do not exit CONFIG_9P_FS_POSIX_ACL"
	try ./scripts/config --enable CONFIG_9P_FS_SECURITY || die "module do not exit CONFIG_9P_FS_SECURITY"
	try ./scripts/config --enable CONFIG_FUSE_FS || die "module do not exit CONFIG_FUSE_FS"

	# =============================================================================
	# 24. Memory Management for VMs
	# =============================================================================
	# Hugepages (critical for VM performance)
	try ./scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE || die "module do not exit CONFIG_TRANSPARENT_HUGEPAGE"
	try ./scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_MADVISE || die "module do not exit CONFIG_TRANSPARENT_HUGEPAGE_MADVISE"
	try ./scripts/config --enable CONFIG_HUGETLBFS || die "module do not exit CONFIG_HUGETLBFS"
	try ./scripts/config --enable CONFIG_HUGETLB_PAGE || die "module do not exit CONFIG_HUGETLB_PAGE"

	# KSM (Kernel Samepage Merging - dedupes VM memory)
	try ./scripts/config --enable CONFIG_KSM || die "module do not exit CONFIG_KSM"

	# Memory hotplug (for adding RAM to running VMs)
	try ./scripts/config --enable CONFIG_MEMORY_HOTPLUG || die "module do not exit CONFIG_MEMORY_HOTPLUG"
	try ./scripts/config --enable CONFIG_MEMORY_HOTREMOVE || die "module do not exit CONFIG_MEMORY_HOTREMOVE"
	try ./scripts/config --enable CONFIG_ZONE_DEVICE || die "module do not exit CONFIG_ZONE_DEVICE"
	try ./scripts/config --enable CONFIG_DEVICE_PRIVATE || die "module do not exit CONFIG_DEVICE_PRIVATE"
	try ./scripts/config --enable CONFIG_DEVICE_PUBLIC || die "module do not exit CONFIG_DEVICE_PUBLIC"

	# Swap
	try ./scripts/config --enable CONFIG_SWAP || die "module do not exit CONFIG_SWAP"

	# =============================================================================
	# 25. Cgroups (managing many VMs)
	# =============================================================================
	try ./scripts/config --enable CONFIG_CGROUPS || die "module do not exit CONFIG_CGROUPS"
	try ./scripts/config --enable CONFIG_CGROUP_PIDS || die "module do not exit CONFIG_CGROUP_PIDS"
	try ./scripts/config --enable CONFIG_CGROUP_DEVICE || die "module do not exit CONFIG_CGROUP_DEVICE"
	try ./scripts/config --enable CONFIG_CGROUP_FREEZER || die "module do not exit CONFIG_CGROUP_FREEZER"
	try ./scripts/config --enable CONFIG_CGROUP_NET_PRIO || die "module do not exit CONFIG_CGROUP_NET_PRIO"
	try ./scripts/config --enable CONFIG_CGROUP_NET_CLASSID || die "module do not exit CONFIG_CGROUP_NET_CLASSID"
	try ./scripts/config --enable CONFIG_CGROUP_BPF || die "module do not exit CONFIG_CGROUP_BPF"
	try ./scripts/config --enable CONFIG_CGROUP_MISC || die "module do not exit CONFIG_CGROUP_MISC"
	try ./scripts/config --enable CONFIG_CPUSETS || die "module do not exit CONFIG_CPUSETS"
	try ./scripts/config --enable CONFIG_CGROUP_CPUSET || die "module do not exit CONFIG_CGROUP_CPUSET"
	try ./scripts/config --enable CONFIG_CGROUP_SCHED || die "module do not exit CONFIG_CGROUP_SCHED"
	try ./scripts/config --enable CONFIG_FAIR_GROUP_SCHED || die "module do not exit CONFIG_FAIR_GROUP_SCHED"
	try ./scripts/config --enable CONFIG_CFS_BANDWIDTH || die "module do not exit CONFIG_CFS_BANDWIDTH"
	try ./scripts/config --enable CONFIG_RT_GROUP_SCHED || die "module do not exit CONFIG_RT_GROUP_SCHED"

	# =============================================================================
	# 26. Namespaces (containers / isolation)
	# =============================================================================
	try ./scripts/config --enable CONFIG_NAMESPACES || die "module do not exit CONFIG_NAMESPACES"
	try ./scripts/config --enable CONFIG_UTS_NS || die "module do not exit CONFIG_UTS_NS"
	try ./scripts/config --enable CONFIG_IPC_NS || die "module do not exit CONFIG_IPC_NS"
	try ./scripts/config --enable CONFIG_PID_NS || die "module do not exit CONFIG_PID_NS"
	try ./scripts/config --enable CONFIG_NET_NS || die "module do not exit CONFIG_NET_NS"
	try ./scripts/config --enable CONFIG_USER_NS || die "module do not exit CONFIG_USER_NS"

	# =============================================================================
	# 27. TPM (Windows 11 VMs require TPM 2.0)
	# =============================================================================
	try ./scripts/config --enable CONFIG_TCG_TPM || die "module do not exit CONFIG_TCG_TPM"
	try ./scripts/config --enable CONFIG_TCG_TIS || die "module do not exit CONFIG_TCG_TIS"
	try ./scripts/config --enable CONFIG_TCG_TIS_SPI || die "module do not exit CONFIG_TCG_TIS_SPI"
	try ./scripts/config --enable CONFIG_TCG_TIS_I2C || die "module do not exit CONFIG_TCG_TIS_I2C"
	try ./scripts/config --enable CONFIG_TCG_CRB || die "module do not exit CONFIG_TCG_CRB"
	try ./scripts/config --enable CONFIG_TCG_VTPM_PROXY || die "module do not exit CONFIG_TCG_VTPM_PROXY"

	# =============================================================================
	# 28. PCI / PCIe (X670E has PCIe 5.0, hotplug useful for VMs)
	# =============================================================================
	try ./scripts/config --enable CONFIG_PCI || die "module do not exit CONFIG_PCI"
	try ./scripts/config --enable CONFIG_PCI_MSI || die "module do not exit CONFIG_PCI_MSI"
	try ./scripts/config --enable CONFIG_PCI_QUIRKS || die "module do not exit CONFIG_PCI_QUIRKS"
	try ./scripts/config --enable CONFIG_PCIEPORTBUS || die "module do not exit CONFIG_PCIEPORTBUS"
	try ./scripts/config --enable CONFIG_PCIEAER || die "module do not exit CONFIG_PCIEAER"
	try ./scripts/config --enable CONFIG_PCIEASPM || die "module do not exit CONFIG_PCIEASPM"
	try ./scripts/config --enable CONFIG_PCIE_PME || die "module do not exit CONFIG_PCIE_PME"
	try ./scripts/config --enable CONFIG_PCIE_DPC || die "module do not exit CONFIG_PCIE_DPC"
	try ./scripts/config --enable CONFIG_PCIE_PTM || die "module do not exit CONFIG_PCIE_PTM"
	try ./scripts/config --enable CONFIG_PCI_IOV || die "module do not exit CONFIG_PCI_IOV"
	try ./scripts/config --enable CONFIG_HOTPLUG_PCI || die "module do not exit CONFIG_HOTPLUG_PCI"
	try ./scripts/config --enable CONFIG_HOTPLUG_PCI_ACPI || die "module do not exit CONFIG_HOTPLUG_PCI_ACPI"

	# =============================================================================
	# 29. ACPI (for hotplug memory, IO, containers)
	# =============================================================================
	try ./scripts/config --enable CONFIG_ACPI || die "module do not exit CONFIG_ACPI"
	try ./scripts/config --enable CONFIG_ACPI_HOTPLUG_MEMORY || die "module do not exit CONFIG_ACPI_HOTPLUG_MEMORY"
	try ./scripts/config --enable CONFIG_ACPI_HOTPLUG_IO || die "module do not exit CONFIG_ACPI_HOTPLUG_IO"
	try ./scripts/config --enable CONFIG_ACPI_CONTAINER || die "module do not exit CONFIG_ACPI_CONTAINER"

	# =============================================================================
	# 30. NUMA (Ryzen 9 9950X benefits from NUMA awareness)
	# =============================================================================
	try ./scripts/config --enable CONFIG_NUMA || die "module do not exit CONFIG_NUMA"
	try ./scripts/config --enable CONFIG_AMD_NUMA || die "module do not exit CONFIG_AMD_NUMA"
	try ./scripts/config --enable CONFIG_NUMA_BALANCING || die "module do not exit CONFIG_NUMA_BALANCING"
	try ./scripts/config --enable CONFIG_NUMA_BALANCING_DEFAULT_ENABLED || die "module do not exit CONFIG_NUMA_BALANCING_DEFAULT_ENABLED"

	# =============================================================================
	# 31. Block Devices (loop, NBD for VM disk images)
	# =============================================================================
	try ./scripts/config --enable CONFIG_BLK_DEV_LOOP || die "module do not exit CONFIG_BLK_DEV_LOOP"
	try ./scripts/config --enable CONFIG_BLK_DEV_NBD || die "module do not exit CONFIG_BLK_DEV_NBD"

	# =============================================================================
	# 32. IO Schedulers (VM performance)
	# =============================================================================
	try ./scripts/config --enable CONFIG_MQ_IOSCHED_KYBER || die "module do not exit CONFIG_MQ_IOSCHED_KYBER"
	try ./scripts/config --enable CONFIG_IOSCHED_BFQ || die "module do not exit CONFIG_IOSCHED_BFQ"

	# =============================================================================
	# 33. Watchdog (VM stability)
	# =============================================================================
	try ./scripts/config --enable CONFIG_SOFT_WATCHDOG || die "module do not exit CONFIG_SOFT_WATCHDOG"

	# =============================================================================
	# 34. Security / Hardening (standard for modern kernels)
	# =============================================================================
	try ./scripts/config --enable CONFIG_PAGE_TABLE_ISOLATION || die "module do not exit CONFIG_PAGE_TABLE_ISOLATION"
	try ./scripts/config --enable CONFIG_RETPOLINE || die "module do not exit CONFIG_RETPOLINE"
	try ./scripts/config --enable CONFIG_SPECULATION_STORE_BYPASS || die "module do not exit CONFIG_SPECULATION_STORE_BYPASS"
	try ./scripts/config --enable CONFIG_HARDENED_USERCOPY || die "module do not exit CONFIG_HARDENED_USERCOPY"
	try ./scripts/config --enable CONFIG_STACKPROTECTOR || die "module do not exit CONFIG_STACKPROTECTOR"
	try ./scripts/config --enable CONFIG_STACKPROTECTOR_STRONG || die "module do not exit CONFIG_STACKPROTECTOR_STRONG"
	try ./scripts/config --enable CONFIG_RANDOMIZE_BASE || die "module do not exit CONFIG_RANDOMIZE_BASE"
	try ./scripts/config --enable CONFIG_PAGE_POISONING || die "module do not exit CONFIG_PAGE_POISONING"
	try ./scripts/config --enable CONFIG_INIT_ON_ALLOC_DEFAULT_ON || die "module do not exit CONFIG_INIT_ON_ALLOC_DEFAULT_ON"
	try ./scripts/config --enable CONFIG_INIT_ON_FREE_DEFAULT_ON || die "module do not exit CONFIG_INIT_ON_FREE_DEFAULT_ON"

	# =============================================================================
	# 35. Slab allocator
	# =============================================================================
	try ./scripts/config --enable CONFIG_SLUB || die "module do not exit CONFIG_SLUB"
	try ./scripts/config --enable CONFIG_SLUB_CPU_PARTIAL || die "module do not exit CONFIG_SLUB_CPU_PARTIAL"

	# =============================================================================
	# Devtmpfs (required for /dev/disk/by-uuid/ in initramfs)
	# =============================================================================
	try ./scripts/config --enable CONFIG_DEVTMPFS || die "Failed to set CONFIG_DEVTMPFS"
	try ./scripts/config --enable CONFIG_DEVTMPFS_MOUNT || die "Failed to set CONFIG_DEVTMPFS_MOUNT"
	
	# =============================================================================
	# END OF CONFIGURATION
	# =============================================================================
	# Post-build notes:
	#   1. Add to /etc/modprobe.d/kvm.conf:
	#        options kvm_amd nested=1
	#
	#   2. For VFIO GPU passthrough with RTX 3090:
	#      - If you have a SECOND GPU for the host: add to kernel cmdline:
	#          amd_iommu=on iommu=pt vfio-pci.ids=10de:XXXX,10de:YYYY
	#        (get IDs from: lspci -nn | grep -i nvidia)
	#      - If you only have the RTX 3090 (single-GPU passthrough):
	#        DO NOT add vfio-pci to ugrd. Use a hook script to unbind nvidia
	#        and bind vfio-pci AFTER boot / before starting the VM.
	#
	#   3. WARNING: Since kernel 6.0, loading VFIO in initramfs can freeze
	#      the framebuffer. With GPG encryption in ugrd, this means you may
	#      not see the passphrase prompt. Test with a fallback unlock method
	#      (serial console, SSH, or second GPU) before relying on this.
	# =============================================================================
}
