#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

BUILDROOT_VERSION="2026.02"
BUILDROOT_DIR="${OUTPUT_DIR}/buildroot-${BUILDROOT_VERSION}"
STAMP_DIR="${OUTPUT_DIR}/.stamps"

if [ ! -f "${STAMP_DIR}/02-patch-buildroot" ]; then
    echo "Run 02-patch-buildroot.sh first."
    exit 1
fi

JOBS="$(nproc)"
if [ "${JOBS}" -gt 8 ]; then
    JOBS=8
fi

echo "Configuring buildroot (stm32f429_disco_xip_defconfig)..."
make -C "${BUILDROOT_DIR}" stm32f429_disco_xip_defconfig

echo "Building buildroot (toolchain + kernel + bootloader + rootfs + adbd)..."
echo "    This will take a while on first run (toolchain build is slow)."
make -C "${BUILDROOT_DIR}" -j"${JOBS}"

echo "Buildroot build complete."
touch "${STAMP_DIR}/03-build-buildroot"
