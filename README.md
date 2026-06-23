# stm32f429-adbd

Cross-build a minimal **noMMU Linux + adbd** for the **STM32F429I-DISC1** board.

```
just
Available recipes:
    all                        # Full build from source fetch to flashable images
    build                      # Step 3: Build buildroot (toolchain + kernel + bootloader + rootfs + adbd)
    clean *args                # just clean --all   - also remove downloaded sources
    fetch                      # Step 1: Download buildroot tarball
    flash                      # Flash afboot + DTB + kernel + romfs to board via OpenOCD/ST-Link
    initromfs                  # Step 3b: Build minimal romfs initfs for on-chip flash (after build)
    initromfs-all              # Build minimal romfs initfs (after build)
    list                       # Show available commands
    patch                      # Step 2: Apply buildroot configuration and patches
    qemu-build                 # Step 4: Build the rota1001/qemu-fork emulator (arm-softmmu only)
    qemu-run                   # Step 7: Boot the system under QEMU (requires build + qemu-build)
    rebuild                    # Clean and rebuild from scratch
    sd-card dev="/dev/mmcblk0" # Write rootfs.ext2 to TF card at /dev/mmcblk0 (no root required)
  ```
