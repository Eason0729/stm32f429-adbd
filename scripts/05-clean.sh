#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/output"

echo "Cleaning build artifacts..."

rm -rf "${OUTPUT_DIR}"

echo "Clean complete."
