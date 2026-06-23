#!/usr/bin/env bash
# Build a minimal romfs initfs for on-chip flash.
#
# The flash romfs partition is only 448 KB (0x70000) at 0x08190000.
# The full rootfs (adbd + OpenSSL + libstdc++) goes on the SD card (ext2).
# This script assembles a tiny romfs containing only:
#   - /init (compiled C binary that mounts the SD card and pivots root)
#   - /bin/busybox (for shell and utilities after pivot)
#   - /lib/* (uClibc dynamic libraries for busybox)
#
# Usage: ./scripts/08-build-initromfs.sh
# Output: output/buildroot-2026.02/output/images/rootfs.romfs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
BUILDROOT_DIR="${ROOT_DIR}/output/buildroot-2026.02"
TARGET_DIR="${BUILDROOT_DIR}/output/target"
IMAGES_DIR="${BUILDROOT_DIR}/output/images"
GENROMFS="${BUILDROOT_DIR}/output/host/bin/genromfs"

INITROMFS_DIR="${ROOT_DIR}/output/initromfs"
ROMFS_OUT="${IMAGES_DIR}/rootfs.romfs"

if [ ! -x "${GENROMFS}" ]; then
    echo "ERROR: genromfs not found at ${GENROMFS}"
    echo "Run 'just build' first."
    exit 1
fi

if [ ! -f "${TARGET_DIR}/bin/busybox" ]; then
    echo "ERROR: busybox not found in ${TARGET_DIR}"
    echo "Run 'just build' first."
    exit 1
fi

echo "Building init binary..."
make -C "${ROOT_DIR}/init" clean >/dev/null 2>&1 || true
make -C "${ROOT_DIR}/init" >/dev/null

if [ ! -f "${ROOT_DIR}/init/init" ]; then
    echo "ERROR: init binary build failed."
    exit 1
fi

echo "Building minimal romfs initfs..."

rm -rf "${INITROMFS_DIR}"
mkdir -p "${INITROMFS_DIR}"/{bin,dev,lib,mnt,proc,run,sys,tmp,usr/bin,usr/sbin}

# Copy the compiled init binary (dynamically linked, ~5KB)
cp "${ROOT_DIR}/init/init" "${INITROMFS_DIR}/init"
chmod +x "${INITROMFS_DIR}/init"

# bFLT: everything is statically linked — no shared libs to copy.

# Generate romfs
"${GENROMFS}" -d "${INITROMFS_DIR}" -f "${ROMFS_OUT}"

ROMFS_SIZE=$(stat -c%s "${ROMFS_OUT}")
ROMFS_MAX=$((0x70000))

echo "romfs: ${ROMFS_SIZE} bytes (max ${ROMFS_MAX})"
if [ "${ROMFS_SIZE}" -gt "${ROMFS_MAX}" ]; then
    echo "ERROR: romfs (${ROMFS_SIZE}) exceeds flash partition (${ROMFS_MAX})"
    exit 1
fi

echo "Minimal romfs initfs ready at ${ROMFS_OUT}"
