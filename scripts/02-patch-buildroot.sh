#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

BUILDROOT_VERSION="2026.02"
BUILDROOT_DIR="${OUTPUT_DIR}/buildroot-${BUILDROOT_VERSION}"
PATCH_DIR="${ROOT_DIR}/patches"
CONF_DIR="${ROOT_DIR}/conf"
STAMP_DIR="${OUTPUT_DIR}/.stamps"

if [ ! -f "${STAMP_DIR}/01-fetch-sources" ]; then
    echo "Run 01-fetch-sources.sh first."
    exit 1
fi

mkdir -p "${STAMP_DIR}"

if [ -f "${STAMP_DIR}/02-patch-buildroot" ]; then
    echo "Buildroot already patched (stamp present)."
    exit 0
fi

echo "Applying buildroot source patches..."
cd "${BUILDROOT_DIR}"
for p in "${PATCH_DIR}"/buildroot/*.patch; do
    echo "    Applying $(basename "${p}")..."
    # -N (forward only) skips already-applied patches; tolerate that case.
    patch -p1 -N <"${p}" || true
    rm -f ./*.rej 2>/dev/null || true
done
cd "${ROOT_DIR}"

echo "Installing new adbd source into package/adbd/..."
rm -rf "${BUILDROOT_DIR}"/package/adbd/src \
       "${BUILDROOT_DIR}"/package/adbd/include \
       "${BUILDROOT_DIR}"/package/adbd/Makefile \
       "${BUILDROOT_DIR}"/package/adbd/start_adbd.sh \
       "${BUILDROOT_DIR}"/package/adbd/*.patch \
       "${BUILDROOT_DIR}"/package/adbd/adbd.hash \
       "${BUILDROOT_DIR}"/package/adbd/adbd.hash.rej
cp -a "${ROOT_DIR}"/adbd/src       "${BUILDROOT_DIR}/package/adbd/"
cp -a "${ROOT_DIR}"/adbd/include   "${BUILDROOT_DIR}/package/adbd/"
cp     "${ROOT_DIR}"/adbd/Makefile       "${BUILDROOT_DIR}/package/adbd/"
cp     "${ROOT_DIR}"/adbd/start_adbd.sh  "${BUILDROOT_DIR}/package/adbd/"

echo "Installing gcc patches into package/gcc/14.3.0/..."
if ls "${PATCH_DIR}"/gcc/*.patch 2>/dev/null; then
    cp -a "${PATCH_DIR}"/gcc/*.patch "${BUILDROOT_DIR}/package/gcc/14.3.0/"
fi

echo "Installing uclibc patches into package/uclibc/..."
if ls "${PATCH_DIR}"/uclibc/*.patch 2>/dev/null; then
    cp -a "${PATCH_DIR}"/uclibc/*.patch "${BUILDROOT_DIR}/package/uclibc/"
fi

echo "Installing buildroot.config as defconfig..."
cp "${CONF_DIR}/buildroot.config" \
    "${BUILDROOT_DIR}/configs/stm32f429_disco_xip_defconfig"

echo "Copying linux.config to board directory..."
cp "${CONF_DIR}/linux.config" \
    "${BUILDROOT_DIR}/board/stmicroelectronics/stm32f429-disco/"

echo "Copying busybox-minimal.config..."
cp "${CONF_DIR}/busybox-minimal.config" \
    "${BUILDROOT_DIR}/package/busybox/"

echo "Copying uClibc-ng.config..."
cp "${CONF_DIR}/uClibc-ng.config" \
    "${BUILDROOT_DIR}/package/uclibc/"

echo "Copying linux kernel patches to board directory..."
KERNEL_PATCH_DIR="${BUILDROOT_DIR}/board/stmicroelectronics/stm32f429-disco/patches/linux"
mkdir -p "${KERNEL_PATCH_DIR}"
cp -a "${PATCH_DIR}"/linux/*.patch "${KERNEL_PATCH_DIR}/"

echo "Buildroot patches applied."
touch "${STAMP_DIR}/02-patch-buildroot"
