#!/bin/bash
# Prepare the TF card at /dev/mmcblk0 for STM32F429I-DISC1 SPI MMC boot.
#
# The kernel boots from romfs in on-chip flash and mounts /dev/mmcblk0
# (the TF card accessed via SPI4) as the writable rootfs. This script
# writes the ext2 rootfs image produced by buildroot to the TF card.
#
# No root required: relies on a udev rule granting write access to
# /dev/mmcblk0 (and its partition nodes) for the console user.
#
# WARNING: This DESTROYS all data on /dev/mmcblk0!

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

BUILDROOT_DIR="${ROOT_DIR}/output/buildroot-2026.02"
IMAGE="${BUILDROOT_DIR}/output/images/rootfs.ext2"
DEV="${1:-/dev/mmcblk0}"

if [ ! -f "${IMAGE}" ]; then
    echo "ERROR: rootfs.ext2 not found at ${IMAGE}"
    echo "Run 'just build' first."
    exit 1
fi

if [ ! -b "${DEV}" ]; then
    echo "ERROR: ${DEV} is not a block device."
    exit 1
fi

# Check we can write to the device (udev rule should grant this).
if [ ! -w "${DEV}" ]; then
    echo "ERROR: ${DEV} is not writable by $(whoami)."
    echo "Check the udev rule (e.g. /etc/udev/rules.d/99-mmcblk.rules):"
    echo "  KERNEL==\"mmcblk0\", SUBSYSTEM==\"block\", MODE=\"0666\""
    exit 1
fi

echo "Image: ${IMAGE} ($(stat -c%s "${IMAGE}") bytes)"

dd if="${IMAGE}" of="${DEV}" bs=1M status=progress conv=fsync

sync

echo "  TF card is ready!"
