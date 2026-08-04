# MOST BE ROOT

```
# Sync portage
emerge --sync

# Update kernel source (if new)
emerge -1u gentoo-sources

# Go to new source
cd /usr/src/linux

# Copy old config (optional)
cp ../linux-6.12.9/.config . # or use `make oldconfig`

# Make oldconfig to handle new symbols (interactive if needed)
make olddefconfig # or menuconfig, etc.

# Build
make -j$(nproc)

# Install modules
make modules_install

# Install kernel (copies to /efi, generates initramfs via ugrd)
make install

# Reboot to test the new kernel
reboot
```