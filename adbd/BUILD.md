# cross compiling

## Notes

- **auth** is disabled by passing `NO_AUTH=1` and `-DADBD_NO_AUTH`.
  `NO_AUTH=1` excludes `adb_auth_client.c` from the build and drops
  `-lcrypto`/`-lcrypt` from the link line. `-DADBD_NO_AUTH` switches
  auth function declarations to no-op inline stubs.
- **FORKEXEC** is replaced by **VFORKEXEC** (noMMU target: vfork-only, no PTY).
  `-UHAVE_FORKEXEC` undefines the default, and `-DHAVE_VFORKEXEC=1` enables vfork.
  `-DADBD_NO_PTY` disables PTY allocation (pipe mode instead).
- **TCP listener** is disabled by `-DADBD_NO_LISTENER` (or `NO_LISTENER=1`).
  Skips the `tcp:5037` command socket; USB-only mode.

```bash
export TOOLCHAIN_DIR=$(readlink -f toolchain) && export PATH="$TOOLCHAIN_DIR:$PATH" && \
make clean && \
make CROSS_COMPILE=arm-linux- NO_AUTH=1 \
  CFLAGS="-Os -ffunction-sections -fdata-sections -flto=auto \
          -fno-unwind-tables -fno-asynchronous-unwind-tables \
          -Wno-deprecated-declarations \
          -DADBD_NO_AUTH -DADBD_NO_PTY -DADBD_NO_LISTENER -UHAVE_FORKEXEC -DHAVE_VFORKEXEC=1" \
  LDFLAGS="-static -Wl,--gc-sections -Wl,--strip-all \
           -Wl,--dynamic-linker=/lib/ld-uClibc.so.1 \
           -flto=auto -Wl,--no-eh-frame-hdr"
```
