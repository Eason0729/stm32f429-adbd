#!/bin/sh

SERIAL="2501ABCDEFGHIJ"

GADGET=/sys/kernel/config/usb_gadget/g1

# 1. Create gadget if not exists
if [ ! -d "$GADGET" ]; then
    mkdir -p "$GADGET"
    echo 0x18d1 >"$GADGET"/idVendor
    echo 0x4E26 >"$GADGET"/idProduct
    mkdir -p "$GADGET"/strings/0x409
    echo "ST" >"$GADGET"/strings/0x409/manufacturer
    echo "STM32" >"$GADGET"/strings/0x409/product
    mkdir -p "$GADGET"/functions/ffs.adb
    mkdir -p "$GADGET"/configs/c.1/strings/0x409
    echo "adb" >"$GADGET"/configs/c.1/strings/0x409/configuration
    echo 120 >"$GADGET"/configs/c.1/MaxPower
    ln -sf "$GADGET"/functions/ffs.adb "$GADGET"/configs/c.1/f1
fi

# 2. Mount functionfs
mkdir -p /dev/usb-ffs/adb
mount -t functionfs adb /dev/usb-ffs/adb 2>/dev/null

# 3. Start adbd (opens ep0, writes descriptors)
adbd &

# 4. Fake serial number
echo "$SERIAL" >"$GADGET"/strings/0x409/serialnumber

# 5. Wait for adbd to init, then enable UDC
sleep 3
UDC=$(ls /sys/class/udc)
echo "$UDC" >"$GADGET"/UDC
