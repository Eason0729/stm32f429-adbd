#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

BUILDROOT_VERSION="2026.02"
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz"

STAMP_DIR="${OUTPUT_DIR}/.stamps"
mkdir -p "${STAMP_DIR}"

BUILDROOT_TAR="${OUTPUT_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"
BUILDROOT_DIR="${OUTPUT_DIR}/buildroot-${BUILDROOT_VERSION}"

if [ ! -f "${BUILDROOT_TAR}" ]; then
    echo "Downloading buildroot ${BUILDROOT_VERSION}..."
    wget -q "${BUILDROOT_URL}" -O "${BUILDROOT_TAR}"
fi

if [ ! -d "${BUILDROOT_DIR}" ]; then
    echo "Extracting buildroot..."
    tar xf "${BUILDROOT_TAR}" -C "${OUTPUT_DIR}"
fi

echo "Sources fetched."
touch "${STAMP_DIR}/01-fetch-sources"
