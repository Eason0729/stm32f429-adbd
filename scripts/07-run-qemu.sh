#!/usr/bin/env bash
# Boot the STM32F429I-DISCO system under the rota1001/qemu-fork emulator.
#
# The on-board flash layout is reconstructed in QEMU's emulated flash:
#
#   0x08000000  afboot-stm32 bootloader (stm32f429i-disco.bin)
#   0x08004000  Device Tree Blob (stm32f429-disco.dtb)
#   0x0800C000  XIP kernel (xipImage)
#   0x08190000  romfs initfs (rootfs.romfs)
#
# afboot (loaded via -kernel at address 0 == alias of 0x08000000) sets up
# clocks/FMC and jumps to the kernel at 0x0800C000|1 with r2 = DTB addr.
# The kernel boots from romfs (init=/init) which, on real hardware, would
# pivot to the ext2 TF card; under QEMU the SPI4 MMC SD card (backed by
# rootfs.ext2 via -drive if=sd) provides /dev/mmcblk0 so the pivot succeeds.
# Use --no-sd to boot without an SD card (init falls back to romfs).
#
# Usage:
#   07-run-qemu.sh              # interactive, serial on stdio
#   07-run-qemu.sh --nographic   # same but -nographic
#   07-run-qemu.sh --gdb         # wait for gdb on tcp::1234 before boot
#   07-run-qemu.sh --sd-card <path>  # override SD card image
#   07-run-qemu.sh --no-sd       # boot without SD card

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

QEMU_PREFIX="${OUTPUT_DIR}/qemu"
QEMU_BIN="${QEMU_PREFIX}/bin/qemu-system-arm"
BUILDROOT_DIR="${OUTPUT_DIR}/buildroot-2026.02"
IMAGES_DIR="${BUILDROOT_DIR}/output/images"
STAMP_DIR="${OUTPUT_DIR}/.stamps"

AFBOOT="${IMAGES_DIR}/stm32f429i-disco.bin"
DTB="${IMAGES_DIR}/stm32f429-disco.dtb"
XIPIMAGE="${IMAGES_DIR}/xipImage"
ROMFS="${IMAGES_DIR}/rootfs.romfs"
SD_CARD_IMG="${IMAGES_DIR}/rootfs.ext2"

NOGRAPHIC=0
GDB_WAIT=0
EXTRA_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --nographic)
        NOGRAPHIC=1
        shift
        ;;
    --gdb)
        GDB_WAIT=1
        shift
        ;;
    --sd-card)
        SD_CARD_IMG="$2"
        shift 2
        ;;
    --no-sd)
        SD_CARD_IMG=""
        shift
        ;;
    --*)
        EXTRA_ARGS+=("$1")
        shift
        ;;
    *)
        EXTRA_ARGS+=("$1")
        shift
        ;;
    esac
done

if [ ! -x "${QEMU_BIN}" ]; then
    echo "ERROR: qemu-system-arm not found at ${QEMU_BIN}"
    echo "Run 'just qemu-build' (scripts/04-build-qemu.sh) first."
    exit 1
fi

if [ ! -f "${STAMP_DIR}/03-build-buildroot" ]; then
    echo "ERROR: buildroot has not been built yet."
    echo "Run 'just build' first."
    exit 1
fi

for f in "${AFBOOT}" "${DTB}" "${XIPIMAGE}" "${ROMFS}"; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: missing image: ${f}"
        exit 1
    fi
done

# Sanity: xipImage must fit before the romfs partition at 0x08190000.
XIP_SIZE=$(stat -c%s "${XIPIMAGE}")
PAD_TARGET=$((0x08190000 - 0x0800C000))
if [ "${XIP_SIZE}" -gt "${PAD_TARGET}" ]; then
    echo "ERROR: xipImage (${XIP_SIZE} bytes) exceeds 0x08190000 (cap ${PAD_TARGET} bytes)."
    exit 1
fi

echo "Booting STM32F429I-DISCO under QEMU fork..."
echo "    afboot   @ 0x08000000 ($(stat -c%s "${AFBOOT}") bytes)"
echo "    dtb      @ 0x08004000 ($(stat -c%s "${DTB}") bytes)"
echo "    xipImage @ 0x0800C000 ($(stat -c%s "${XIPIMAGE}") bytes)"
echo "    romfs    @ 0x08190000 ($(stat -c%s "${ROMFS}") bytes)"
if [ -n "${SD_CARD_IMG}" ] && [ -f "${SD_CARD_IMG}" ]; then
    echo "    sd-card  @ ${SD_CARD_IMG} ($(stat -c%s "${SD_CARD_IMG}") bytes)"
else
    echo "    sd-card  (none — init will fall back to romfs)"
fi
echo

# -kernel loads afboot at address 0 (alias of 0x08000000) and sets PC=0.
# The loader devices pre-stage DTB / kernel / romfs into emulated flash
# before the CPU resets; afboot then jumps to 0x0800C000 with r2=0x08004000.
# shellcheck disable=SC2054  # commas are qemu -device key=value pairs, not array separators
ARGS=(
    -machine stm32f429discovery
    -kernel "${AFBOOT}"
    -device loader,file="${DTB}",addr=0x08004000,force-raw=on
    -device loader,file="${XIPIMAGE}",addr=0x0800C000,force-raw=on
    -device loader,file="${ROMFS}",addr=0x08190000,force-raw=on
    -serial stdio
    -monitor none
    -nographic
)

if [ -n "${SD_CARD_IMG}" ] && [ -f "${SD_CARD_IMG}" ]; then
    ARGS+=(-drive "if=sd,format=raw,file=${SD_CARD_IMG}")
fi

if [ "${GDB_WAIT}" -eq 1 ]; then
    ARGS+=(-S -gdb tcp::1234)
fi

if [ "${NOGRAPHIC}" -eq 1 ]; then
    # already -nographic; nothing extra
    :
fi

exec "${QEMU_BIN}" "${ARGS[@]}" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
