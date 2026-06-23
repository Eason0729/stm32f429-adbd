# adbd-cross - Build Linux + adbd for STM32F429I-DISCO
#
# Usage:
#   just fetch       - Download buildroot tarball
#   just patch        - Apply buildroot configuration and patches
#   just build        - Build everything (toolchain + kernel + rootfs + adbd)
#   just initromfs    - Build + create minimal romfs initfs for flash
#   just all          - Fetch + patch + build
#   just qemu-build   - Build rota1001/qemu-fork (arm-softmmu)
#   just qemu-run     - Build + boot the system under QEMU
#   just sd-card      - Write rootfs.ext2 to TF card at /dev/mmcblk0
#   just flash        - Flash afboot+DTB+kernel+romfs to board via OpenOCD
#   just clean        - Remove build artifacts (keeps sources)
#   just clean --all  - Remove everything (incl. downloaded sources)
#   just rebuild      - clean + all
#   just list         - Show this help

root := justfile_directory()

# Show available commands
list:
    @just --list

# Step 1: Download buildroot tarball
fetch:
    @echo "=== Fetching sources ==="
    @{{root}}/scripts/01-fetch-sources.sh

# Step 2: Apply buildroot configuration and patches
patch: fetch
    @echo "=== Applying buildroot patches ==="
    @{{root}}/scripts/02-patch-buildroot.sh

# Step 3: Build buildroot (toolchain + kernel + bootloader + rootfs + adbd)
build: patch
    @echo "=== Building buildroot ==="
    @{{root}}/scripts/03-build-buildroot.sh

# Step 3b: Build minimal romfs initfs for on-chip flash (after build)
initromfs: build
    @echo "=== Building minimal romfs initfs ==="
    @{{root}}/scripts/08-build-initromfs.sh

# Step 4: Build the rota1001/qemu-fork emulator (arm-softmmu only)
qemu-build:
    @echo "=== Building QEMU fork ==="
    @{{root}}/scripts/04-build-qemu.sh

# Step 7: Boot the system under QEMU (requires build + qemu-build)
qemu-run: build qemu-build
    @echo "=== Running under QEMU ==="
    @{{root}}/scripts/07-run-qemu.sh

# Full build from source fetch to flashable images
all: fetch patch build

# Build minimal romfs initfs (after build)
initromfs-all: all
    @{{root}}/scripts/08-build-initromfs.sh

# Write rootfs.ext2 to TF card at /dev/mmcblk0 (no root required)
sd-card dev="/dev/mmcblk0":
    @echo "=== Writing rootfs to SD card ==="
    @{{root}}/scripts/06-flash-sdcard.sh {{dev}}

# Flash afboot + DTB + kernel + romfs to board via OpenOCD/ST-Link
flash: initromfs
    @echo "=== Flashing board via OpenOCD ==="
    @{{root}}/scripts/09-flash-openocd.sh

# Remove build artifacts (keeps downloaded sources)
#   just clean         - only build artifacts
#   just clean --all   - also remove downloaded sources
clean *args:
    @echo "=== Cleaning ==="
    @{{root}}/scripts/05-clean.sh {{args}}

# Clean and rebuild from scratch
rebuild: clean all