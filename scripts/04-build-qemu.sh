#!/usr/bin/env bash
# Build the rota1001/qemu-fork (STM32F429-Discovery machine) for the host.
#
# Only the ARM softmmu target is built (the fork adds the
# "stm32f429discovery" machine there).  The resulting qemu-system-arm is
# installed under output/qemu/bin/.
#
# Sources are cloned (once) into output/qemu-fork-src and built out-of-tree
# in output/qemu-fork-build so re-running this script is cheap once the
# tree is configured.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

QEMU_REPO_URL="https://github.com/rota1001/qemu-fork.git"
QEMU_SRC_DIR="${OUTPUT_DIR}/qemu-fork-src"
QEMU_BUILD_DIR="${OUTPUT_DIR}/qemu-fork-build"
QEMU_PREFIX="${OUTPUT_DIR}/qemu"
STAMP_DIR="${OUTPUT_DIR}/.stamps"

JOBS="$(nproc)"
if [ "${JOBS}" -gt 8 ]; then
    JOBS=8
fi

mkdir -p "${STAMP_DIR}"

echo "Cloning/fetching qemu-fork sources..."
if [ ! -d "${QEMU_SRC_DIR}/.git" ]; then
    git clone --depth 1 "${QEMU_REPO_URL}" "${QEMU_SRC_DIR}"
else
    git -C "${QEMU_SRC_DIR}" fetch --depth 1 origin HEAD
    git -C "${QEMU_SRC_DIR}" reset --hard origin/HEAD
fi

# Apply local patches to the QEMU fork source tree.
QEMU_PATCH_DIR="${ROOT_DIR}/patches/qemu"
QEMU_PATCH_STAMP="${STAMP_DIR}/04-patch-qemu"
if [ -d "${QEMU_PATCH_DIR}" ] && ls "${QEMU_PATCH_DIR}"/*.patch >/dev/null 2>&1; then
    echo "Applying QEMU patches..."
    # Re-apply from a clean tree if the stamp is missing or patch set changed.
    PATCH_SIG=$(cat "${QEMU_PATCH_DIR}"/*.patch | sha256sum | cut -d' ' -f1)
    STAMP_SIG=""
    [ -f "${QEMU_PATCH_STAMP}" ] && STAMP_SIG=$(cat "${QEMU_PATCH_STAMP}")
    if [ "${PATCH_SIG}" != "${STAMP_SIG}" ]; then
        git -C "${QEMU_SRC_DIR}" reset --hard origin/HEAD
        for p in "${QEMU_PATCH_DIR}"/*.patch; do
            patch -d "${QEMU_SRC_DIR}" -p1 <"${p}"
        done
        echo "${PATCH_SIG}" >"${QEMU_PATCH_STAMP}"
    fi
fi

echo "Configuring qemu-fork (arm-softmmu only)..."
mkdir -p "${QEMU_BUILD_DIR}"

# Reconfigure if the install marker is missing or configure flags changed.
if [ ! -f "${QEMU_PREFIX}/bin/qemu-system-arm" ] ||
    [ ! -f "${STAMP_DIR}/04-build-qemu" ]; then
    cd "${QEMU_BUILD_DIR}"
    "${QEMU_SRC_DIR}/configure" \
        --target-list="arm-softmmu" \
        --prefix="${QEMU_PREFIX}" \
        --disable-docs \
        --disable-tools \
        --disable-user \
        --disable-gtk \
        --disable-sdl \
        --disable-vte \
        --disable-capstone \
        --disable-slirp \
        --disable-debug-info \
        --extra-cflags="-O2"
    cd "${ROOT_DIR}"
fi

echo "Building qemu-fork (j${JOBS})..."
ninja -C "${QEMU_BUILD_DIR}" -j "${JOBS}"

echo "Installing qemu-fork into ${QEMU_PREFIX}..."
ninja -C "${QEMU_BUILD_DIR}" install

echo "qemu-system-arm: $("${QEMU_PREFIX}/bin/qemu-system-arm" --version | head -1)"
touch "${STAMP_DIR}/04-build-qemu"
echo "QEMU build complete."
