#!/usr/bin/env bash
# Flash afboot, DTB, XIP kernel, and romfs to STM32F429I-DISCO via OpenOCD/ST-Link.
#
# All partition offsets come exclusively from the compiled DTB — the DTS
# partition table is the single source of truth for the flash layout.
#
# Usage: ./scripts/09-flash-openocd.sh
# Prerequisites: ST-Link connected, OpenOCD installed, 'just build' + 'just initromfs' done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
BUILDROOT_DIR="${ROOT_DIR}/output/buildroot-2026.02"
IMAGES_DIR="${BUILDROOT_DIR}/output/images"

AFBOOT="${IMAGES_DIR}/stm32f429i-disco.bin"
DTB="${IMAGES_DIR}/stm32f429-disco.dtb"
XIPIMAGE="${IMAGES_DIR}/xipImage"
ROMFS="${IMAGES_DIR}/rootfs.romfs"
COMBINED="${IMAGES_DIR}/xip_rootfs_combined.bin"

OPENOCD_BOARD="board/stm32f429discovery.cfg"

for f in "${AFBOOT}" "${DTB}" "${XIPIMAGE}" "${ROMFS}"; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: missing image: ${f}"
        echo "Run 'just build' and 'just initromfs' first."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# DTB-based partition lookup
# ---------------------------------------------------------------------------
if ! command -v fdtget >/dev/null 2>&1; then
    echo "ERROR: fdtget not found. Install device-tree-compiler (dtc)."
    exit 1
fi

# Flash base address and size from DTB
read -r FLASH_PHYS FLASH_SIZE <<<"$(fdtget "${DTB}" /flash@8000000 reg)"
FLASH_END=$((FLASH_PHYS + FLASH_SIZE))

# Read a partition's offset and size by label
read_partition() {
    local label="$1"
    local part_node part_off part_sz
    for part_node in $(fdtget -l "${DTB}" /flash@8000000 2>/dev/null || true); do
        if [ "$(fdtget "${DTB}" "/flash@8000000/${part_node}" label 2>/dev/null || echo "")" = "${label}" ]; then
            read -r part_off part_sz <<<"$(fdtget "${DTB}" "/flash@8000000/${part_node}" reg)"
            printf '%d %d\n' "${part_off}" "${part_sz}"
            return 0
        fi
    done
    return 1
}

# Partition labels expected in the DTS (must exist)
PART_LABELS=(afboot dtb xipimage romfs)
declare -A PART_OFF PART_SZ PART_ADDR

for lbl in "${PART_LABELS[@]}"; do
    read -r off sz < <(read_partition "${lbl}") || {
        echo "ERROR: partition with label '${lbl}' not found in ${DTB}."
        exit 1
    }
    PART_OFF["${lbl}"]=${off}
    PART_SZ["${lbl}"]=${sz}
    PART_ADDR["${lbl}"]=$((FLASH_PHYS + off))
done

# ---------------------------------------------------------------------------
# Fit verification
# ---------------------------------------------------------------------------
XIP_SIZE=$(stat -c%s "${XIPIMAGE}")
ROMFS_SIZE=$(stat -c%s "${ROMFS}")

# (1) Every partition must lie within the flash device
for lbl in "${PART_LABELS[@]}"; do
    part_end=$((PART_ADDR["${lbl}"] + PART_SZ["${lbl}"]))
    if [ "${PART_ADDR["${lbl}"]}" -lt "${FLASH_PHYS}" ] || [ "${part_end}" -gt "${FLASH_END}" ]; then
        echo "ERROR: partition '${lbl}' (0x$(printf '%x' "${PART_ADDR["${lbl}"]}") + 0x$(printf '%x' "${PART_SZ["${lbl}"]}")) exceeds flash bounds (0x$(printf '%x' "${FLASH_PHYS}")–0x$(printf '%x' "${FLASH_END}"))."
        exit 1
    fi
done

# (2) Partitions must not overlap
prev_end=0
for lbl in "${PART_LABELS[@]}"; do
    addr=${PART_ADDR["${lbl}"]}
    end=$((addr + PART_SZ["${lbl}"]))
    if [ "${prev_end}" -gt 0 ] && [ "${addr}" -lt "${prev_end}" ]; then
        echo "ERROR: partition '${lbl}' starts at 0x$(printf '%x' "${addr}") but previous partition ends at 0x$(printf '%x' "${prev_end}")."
        exit 1
    fi
    prev_end=${end}
done

# (3) xipImage fits before romfs partition
COMBINED_ADDR=${PART_ADDR["xipimage"]}
ROMFS_ADDR=${PART_ADDR["romfs"]}
PAD_TARGET=$((ROMFS_ADDR - COMBINED_ADDR))
if [ "${XIP_SIZE}" -gt "${PAD_TARGET}" ]; then
    echo "ERROR: xipImage (${XIP_SIZE} bytes) exceeds space before romfs ($PAD_TARGET bytes)."
    echo "  romfs at 0x$(printf '%x' "${ROMFS_ADDR}") (offset 0x$(printf '%x' "${PART_OFF["romfs"]}"))."
    exit 1
fi

# (4) romfs fits in its partition
if [ "${ROMFS_SIZE}" -gt "${PART_SZ["romfs"]}" ]; then
    echo "ERROR: romfs (${ROMFS_SIZE} bytes) exceeds partition (${PART_SZ["romfs"]} bytes, 0x$(printf '%x' "${PART_SZ["romfs"]}"))."
    exit 1
fi

# (5) Combined image (xipImage + padding + romfs) ends within romfs partition
if [ $((COMBINED_ADDR + PAD_TARGET + ROMFS_SIZE)) -gt $((ROMFS_ADDR + PART_SZ["romfs"])) ]; then
    echo "ERROR: combined image (kernel + pad + romfs) exceeds romfs partition end."
    exit 1
fi

# ---------------------------------------------------------------------------
# Combine and flash
# ---------------------------------------------------------------------------
PAD_BYTES=$((PAD_TARGET - XIP_SIZE))
echo "Creating combined image: xipImage (${XIP_SIZE} bytes) + ${PAD_BYTES} pad + romfs (${ROMFS_SIZE} bytes)"
cp "${XIPIMAGE}" "${COMBINED}"
dd if=/dev/zero bs=1 count="${PAD_BYTES}" 2>/dev/null | tr '\000' '\377' >>"${COMBINED}"
cat "${ROMFS}" >>"${COMBINED}"
echo "Combined image: $(stat -c%s "${COMBINED}") bytes"

echo "Flashing via OpenOCD (ST-Link)..."
echo "    afboot       @ 0x$(printf '%x' "${PART_ADDR["afboot"]}") ($(stat -c%s "${AFBOOT}") bytes)"
echo "    dtb          @ 0x$(printf '%x' "${PART_ADDR["dtb"]}") ($(stat -c%s "${DTB}") bytes)"
echo "    xip+romfs    @ 0x$(printf '%x' "${COMBINED_ADDR}") ($(stat -c%s "${COMBINED}") bytes)"

openocd -f "${OPENOCD_BOARD}" \
    -c "init" \
    -c "reset init" \
    -c "flash probe 0" \
    -c "flash info 0" \
    -c "flash write_image erase ${AFBOOT} 0x$(printf '%x' "${PART_ADDR["afboot"]}")" \
    -c "flash write_image erase ${DTB} 0x$(printf '%x' "${PART_ADDR["dtb"]}")" \
    -c "flash write_image erase ${COMBINED} 0x$(printf '%x' "${COMBINED_ADDR}")" \
    -c "reset run" \
    -c "shutdown"

echo "Flash complete!"
