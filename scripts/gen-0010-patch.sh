#!/usr/bin/env bash
set -euo pipefail

# Generate patch 0010 for switching USB from OTG_HS to OTG_FS.
#
# Usage: scripts/gen-0010-patch.sh
#
# This script:
#   1. Copies the original (pre-patch) DTS files to a temp dir
#   2. Applies the DTS modifications (SDIO→SPI4, OTG_HS→OTG_FS, etc.)
#   3. Diffs original vs modified to produce a git-format-patch
#   4. Writes the patch to patches/linux/0010-Switch-from-SDIO-to-SPI4-MMC-card.patch

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_DIR="${ROOT_DIR}/output/buildroot-2026.02/output/build/linux-7.0"
PATCH_OUT="${ROOT_DIR}/patches/linux/0010-Switch-from-SDIO-to-SPI4-MMC-card.patch"

if [ ! -d "${KERNEL_DIR}" ]; then
    echo "Error: kernel source not found at ${KERNEL_DIR}"
    echo "Run 'just fetch && just patch' first."
    exit 1
fi

DTS_DTS="${KERNEL_DIR}/arch/arm/boot/dts/st/stm32f429-disco.dts"
DTS_PIN="${KERNEL_DIR}/arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ---------------------------------------------------------------------------
# 1. Save originals (pre-patch-0010 state)
# ---------------------------------------------------------------------------
cp "${DTS_DTS}" "${WORK}/stm32f429-disco.dts.orig"
cp "${DTS_PIN}" "${WORK}/stm32f4-pinctrl.dtsi.orig"

# ---------------------------------------------------------------------------
# 2. Create modified versions
# ---------------------------------------------------------------------------
cp "${WORK}/stm32f429-disco.dts.orig" "${WORK}/stm32f429-disco.dts.new"
cp "${WORK}/stm32f4-pinctrl.dtsi.orig" "${WORK}/stm32f4-pinctrl.dtsi.new"

# Use python for reliable multi-line replacements
cat > "${WORK}/apply_changes.py" << PYEOF
import os

WORK = "${WORK}"

# --- stm32f429-disco.dts ---
with open(f"{WORK}/stm32f429-disco.dts.new", 'r') as f:
    dts = f.read()

# Hunk 1: &sdio → &spi4
old_sdio = """&sdio {
\tstatus = "okay";
\tpinctrl-names = "default", "opendrain";
\tpinctrl-0 = <&sdio_pins>;
\tpinctrl-1 = <&sdio_pins_od>;
\tbus-width = <1>;
\tmax-frequency = <1000000>;
\tbroken-cd;
\tvmmc-supply = <&v3v3>;
};"""
new_spi4 = """&spi4 {
\tstatus = "okay";
\tpinctrl-names = "default";
\tpinctrl-0 = <&spi4_pins>;
\tcs-gpios = <&gpioe 4 GPIO_ACTIVE_LOW>;

\tmmc-slot@0 {
\t\tcompatible = "mmc-spi-slot";
\t\treg = <0>;
\t\tspi-max-frequency = <12000000>;
\t\tvoltage-ranges = <3000 3500>;
\t\tbroken-cd;
\t};
};"""
assert old_sdio in dts, "Cannot find &sdio block"
dts = dts.replace(old_sdio, new_spi4, 1)

# Hunk 2: i2c3 status okay → disabled
old_i2c3 = """\tclock-frequency = <100000>;
\tstatus = "okay";"""
new_i2c3 = """\tclock-frequency = <100000>;
\tstatus = "disabled";"""
assert old_i2c3 in dts, "Cannot find i2c3 status"
dts = dts.replace(old_i2c3, new_i2c3, 1)

# Hunk 3: ltdc status okay → disabled
old_ltdc = """&ltdc {
\tstatus = "okay";"""
new_ltdc = """&ltdc {
\tstatus = "disabled";"""
assert old_ltdc in dts, "Cannot find ltdc status"
dts = dts.replace(old_ltdc, new_ltdc, 1)

# Hunk 4: &usbotg_hs (host) → &usbotg_fs (peripheral)
old_usbotg = """&usbotg_hs {
\tcompatible = "st,stm32f4x9-fsotg";
\tdr_mode = "host";
\tpinctrl-0 = <&usbotg_fs_pins_b>;
\tpinctrl-names = "default";
\tstatus = "okay";
};"""
new_usbotg = """&usbotg_fs {
\tdr_mode = "peripheral";
\tpinctrl-0 = <&usbotg_fs_pins_periph>;
\tpinctrl-names = "default";
\tstatus = "okay";
};"""
assert old_usbotg in dts, "Cannot find &usbotg_hs block"
dts = dts.replace(old_usbotg, new_usbotg, 1)

with open(f"{WORK}/stm32f429-disco.dts.new", 'w') as f:
    f.write(dts)

# --- stm32f4-pinctrl.dtsi ---
with open(f"{WORK}/stm32f4-pinctrl.dtsi.new", 'r') as f:
    pin = f.read()

# Add usbotg_fs_pins_periph before usbotg_fs_pins_b
old_pin_insert = """\t\t\tusbotg_fs_pins_b: usbotg-fs-1 {"""
new_pin_insert = """\t\t\tusbotg_fs_pins_periph: usbotg-fs-periph {
\t\t\t\tpins {
\t\t\t\t\tpinmux = <STM32_PINMUX('A', 11, AF10)>, /* OTG_FS_DM */
\t\t\t\t\t\t <STM32_PINMUX('A', 12, AF10)>; /* OTG_FS_DP */
\t\t\t\t\tbias-disable;
\t\t\t\t\tdrive-push-pull;
\t\t\t\t\tslew-rate = <2>;
\t\t\t\t};
\t\t\t};

\t\t\tusbotg_fs_pins_b: usbotg-fs-1 {"""
assert old_pin_insert in pin, "Cannot find usbotg_fs_pins_b"
pin = pin.replace(old_pin_insert, new_pin_insert, 1)

# Add spi4_pins before i2c3_pins
old_spi4_insert = """\t\t\ti2c3_pins: i2c3-0 {"""
new_spi4_insert = """\t\t\tspi4_pins: spi4-0 {
\t\t\t\tpins1 {
\t\t\t\t\tpinmux = <STM32_PINMUX('E', 2, AF5)>, /* SPI4_SCK */
\t\t\t\t\t\t <STM32_PINMUX('E', 6, AF5)>; /* SPI4_MOSI */
\t\t\t\t\tbias-disable;
\t\t\t\t\tdrive-push-pull;
\t\t\t\t\tslew-rate = <0>;
\t\t\t\t};
\t\t\t\tpins2 {
\t\t\t\t\tpinmux = <STM32_PINMUX('E', 5, AF5)>; /* SPI4_MISO */
\t\t\t\t\tbias-pull-up;
\t\t\t\t};
\t\t\t};

\t\t\ti2c3_pins: i2c3-0 {"""
assert old_spi4_insert in pin, "Cannot find i2c3_pins"
pin = pin.replace(old_spi4_insert, new_spi4_insert, 1)

with open(f"{WORK}/stm32f4-pinctrl.dtsi.new", 'w') as f:
    f.write(pin)

print("DTS modifications applied successfully")
PYEOF

python3 "${WORK}/apply_changes.py"

# ---------------------------------------------------------------------------
# 3. Generate git-format-patch style output
# ---------------------------------------------------------------------------
DTS_DIFF=$(diff -u \
    --label "a/arch/arm/boot/dts/st/stm32f429-disco.dts" \
    --label "b/arch/arm/boot/dts/st/stm32f429-disco.dts" \
    "${WORK}/stm32f429-disco.dts.orig" \
    "${WORK}/stm32f429-disco.dts.new" || true)

PIN_DIFF=$(diff -u \
    --label "a/arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi" \
    --label "b/arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi" \
    "${WORK}/stm32f4-pinctrl.dtsi.orig" \
    "${WORK}/stm32f4-pinctrl.dtsi.new" || true)

# Count insertions and deletions
DTS_ADD=$(echo "$DTS_DIFF" | grep -c '^+[^+]' || true)
DTS_DEL=$(echo "$DTS_DIFF" | grep -c '^-[^-]' || true)
PIN_ADD=$(echo "$PIN_DIFF" | grep -c '^+[^+]' || true)
PIN_DEL=$(echo "$PIN_DIFF" | grep -c '^-[^-]' || true)
TOTAL_ADD=$((DTS_ADD + PIN_ADD))
TOTAL_DEL=$((DTS_DEL + PIN_DEL))

{
echo "From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001"
echo "From: Eason <30045503+Eason0729@users.noreply.github.com>"
echo "Date: Sun, 3 May 2026 00:00:00 +0800"
echo "Subject: [PATCH] Switch from SDIO to SPI4 MMC card, disable display,"
echo " add USB gadget on OTG_FS"
echo ""
echo "- Replace SDIO with SPI4 MMC (mmc_spi) at 12 MHz on PE2/PE4/PE5/PE6"
echo "- Disable LTDC display and I2C3 touchscreen to save space"
echo "- Enable OTG_FS (0x50000000) in peripheral mode for adbd on PA11/PA12"
echo "  (the USB connector is wired to OTG_FS, not OTG_HS)"
echo "- Add spi4_pins and usbotg_fs_pins_periph pinctrl groups"
echo ""
echo "Signed-off-by: 邱繼叡 Eason CHIU <30045503+Eason0729@users.noreply.github.com>"
echo "---"
echo " arch/arm/boot/dts/st/stm32f429-disco.dts  | ${DTS_ADD} +${DTS_DEL}"
echo " arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi | ${PIN_ADD} +${PIN_DEL}"
echo " 2 files changed, ${TOTAL_ADD} insertions(+), ${TOTAL_DEL} deletions(-)"
echo ""
echo "diff --git a/arch/arm/boot/dts/st/stm32f429-disco.dts b/arch/arm/boot/dts/st/stm32f429-disco.dts"
echo "index cda8a951d..1b5228f84 100644"
echo "$DTS_DIFF"
echo ""
echo "diff --git a/arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi b/arch/arm/boot/dts/st/stm32f4-pinctrl.dtsi"
echo "index befe48909..7828d7330 100644"
echo "$PIN_DIFF"
} > "${PATCH_OUT}"

echo "Patch written to: ${PATCH_OUT}"
echo ""
echo "=== Patch summary ==="
echo "DTS:    +${DTS_ADD} -${DTS_DEL}"
echo "Pinctrl: +${PIN_ADD} -${PIN_DEL}"
echo "Total:  +${TOTAL_ADD} -${TOTAL_DEL}"