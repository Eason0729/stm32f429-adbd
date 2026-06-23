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
BUILDROOT_TAR="${OUTPUT_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"

QEMU_SRC_DIR="${OUTPUT_DIR}/qemu-fork-src"

usage() {
    echo "Usage: $0 [--qemu] <subject>"
    echo ""
    echo "  --qemu   Generate a patch for the QEMU fork source tree"
    echo "           (edits under ${QEMU_SRC_DIR}/)."
    echo "  subject  Patch filename slug and commit Subject line."
    echo ""
    echo "Workflow (buildroot):"
    echo "  1. Edit files under ${BUILDROOT_DIR}/"
    echo "  2. Run this script with a short subject"
    echo "  3. New patches appear under ${PATCH_DIR}/{buildroot,adbd}/"
    echo ""
    echo "Workflow (qemu):"
    echo "  1. Edit files under ${QEMU_SRC_DIR}/"
    echo "  2. Run: $0 --qemu \"<subject>\""
    echo "  3. New patch appears under ${PATCH_DIR}/qemu/"
    exit 2
}

QEMU_MODE=0
if [ "$#" -eq 2 ] && [ "$1" = "--qemu" ]; then
    QEMU_MODE=1
    SUBJECT="$2"
elif [ "$#" -eq 1 ] && [ "$1" != "--help" ] && [ "$1" != "-h" ]; then
    SUBJECT="$1"
else
    usage
fi

slugify() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -c '[:alnum:]' '-' |
        tr -s '-' |
        sed 's/^-//; s/-$//'
}

next_number() {
    local dir="$1" max=0 n name
    local f
    for f in "${dir}"/[0-9][0-9][0-9][0-9]-*.patch; do
        [ -e "$f" ] || continue
        name="${f##*/}"
        n=$((10#${name:0:4}))
        ((n > max)) && max=$n
    done
    printf '%04d' $((max + 1))
}

GENERATED=0

emit_patch() {
    local out_dir="$1" num out
    num="$(next_number "${out_dir}")"
    out="${out_dir}/${num}-$(slugify "${SUBJECT}").patch"
    git format-patch -1 HEAD --stdout >"${out}"
    echo "    ${out}"
    GENERATED=$((GENERATED + 1))
}

# ---------------------------------------------------------------------------
# QEMU mode
# ---------------------------------------------------------------------------
if [ "${QEMU_MODE}" -eq 1 ]; then
    if [ ! -d "${QEMU_SRC_DIR}/.git" ]; then
        echo "Missing ${QEMU_SRC_DIR}. Run 'just qemu-build' first."
        exit 1
    fi

    WORK_DIR=$(mktemp -d)
    trap 'rm -rf "${WORK_DIR}"' EXIT

    QEMU_WORK_DIR="${WORK_DIR}/qemu-fork"
    echo "Cloning fresh qemu-fork into ${WORK_DIR}"
    git clone --depth 1 "${QEMU_SRC_DIR}" "${QEMU_WORK_DIR}" 2>/dev/null

    echo "Applying existing patches/qemu/* to baseline"
    cd "${QEMU_WORK_DIR}"
    for p in "${PATCH_DIR}"/qemu/*.patch; do
        [ -e "$p" ] || continue
        patch -p1 -N <"${p}" >/dev/null 2>&1 || true
        rm -f ./*.rej 2>/dev/null || true
    done

    echo "Initializing git repo in baseline"
    git config user.email "adbd-cross@example.local"
    git config user.name "adbd-cross"
    git add -A
    git commit -q --allow-empty -m "baseline"

    echo "Syncing user modifications from ${QEMU_SRC_DIR}"
    rsync -a --delete \
        --exclude='/.git' \
        --exclude='/build' \
        "${QEMU_SRC_DIR}/" "${QEMU_WORK_DIR}/"

    echo "Generating patches:"
    git add -A
    if ! git diff --cached --quiet; then
        git commit -q -m "${SUBJECT}"
        emit_patch "${PATCH_DIR}/qemu"
    fi

    if [ "${GENERATED}" -eq 0 ]; then
        echo "    No changes detected."
    fi
    echo "Done. Patches generated: ${GENERATED}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Buildroot mode (default)
# ---------------------------------------------------------------------------
if [ ! -f "${BUILDROOT_TAR}" ]; then
    echo "Missing ${BUILDROOT_TAR}. Run 'just fetch' first."
    exit 1
fi
if [ ! -d "${BUILDROOT_DIR}" ]; then
    echo "Missing ${BUILDROOT_DIR}. Run 'just patch' first."
    exit 1
fi
if [ ! -f "${STAMP_DIR}/02-patch-buildroot" ]; then
    echo "Missing 02-patch-buildroot stamp. Run 'just patch' first."
    exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "Preparing fresh buildroot in ${WORK_DIR}"
BUILDROOT_WORK_DIR="${WORK_DIR}/buildroot"
mkdir -p "${BUILDROOT_WORK_DIR}"
tar xf "${BUILDROOT_TAR}" -C "${BUILDROOT_WORK_DIR}" --strip-components=1

echo "Replicating post-02 state into baseline"
cd "${BUILDROOT_WORK_DIR}"
for p in "${PATCH_DIR}"/buildroot/*.patch; do
    [ -e "$p" ] || continue
    patch -p1 -N <"${p}" >/dev/null 2>&1 || true
    rm -f ./*.rej 2>/dev/null || true
done
mkdir -p package/adbd
rm -f package/adbd/*.patch
cp -a "${PATCH_DIR}"/adbd/*.patch package/adbd/ 2>/dev/null || true
if ls "${PATCH_DIR}"/gcc/*.patch 2>/dev/null; then
    cp -a "${PATCH_DIR}"/gcc/*.patch package/gcc/14.3.0/
fi
cp "${CONF_DIR}/buildroot.config" configs/stm32f429_disco_xip_defconfig
cp "${CONF_DIR}/linux.config" board/stmicroelectronics/stm32f429-disco/
cp "${CONF_DIR}/busybox-minimal.config" package/busybox/
cp "${CONF_DIR}/uClibc-ng.config" package/uclibc/
KERNEL_PATCH_DIR="board/stmicroelectronics/stm32f429-disco/patches/linux"
mkdir -p "${KERNEL_PATCH_DIR}"
cp -a "${PATCH_DIR}"/linux/*.patch "${KERNEL_PATCH_DIR}/"

echo "Initializing git repo in baseline"
git init -q
git config user.email "adbd-cross@example.local"
git config user.name "stm32f429-adbd"
git add -A
git commit -q -m "baseline"

echo "Syncing user modifications from ${BUILDROOT_DIR}"
rsync -a --delete \
    --exclude='/output' \
    --exclude='/.git' \
    "${BUILDROOT_DIR}/" "${BUILDROOT_WORK_DIR}/"

echo "Generating patches:"
git add -A -- package/adbd
if ! git diff --cached --quiet; then
    git commit -q -m "${SUBJECT}"
    emit_patch "${PATCH_DIR}/adbd"
    git reset -q --soft HEAD~1
fi
git reset -q -- package/adbd

git add -A
git reset -q -- package/adbd
if ! git diff --cached --quiet; then
    git commit -q -m "${SUBJECT}"
    emit_patch "${PATCH_DIR}/buildroot"
fi

if [ "${GENERATED}" -eq 0 ]; then
    echo "    No changes detected."
fi

echo "Done. Patches generated: ${GENERATED}"
