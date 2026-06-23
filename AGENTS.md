`stm32f429-adbd` — cross-builds a minimal noMMU Linux + adbd for the
STM32F429I-DISCO board using buildroot 2026.02.

## Skill

- stm32 skill
- repo-explorer skill

## Layout

- `scripts/`  — pipeline scripts (`01-fetch` → `02-patch` → `03-build`,
  `04-build-qemu`, `05-clean.sh`, `06-flash-sdcard.sh`, `07-run-qemu.sh`,
  `gen-patches.sh`).
- `patches/`  — ordered patch series: `buildroot/`, `adbd/`, `gcc/`, `linux/`, `qemu/`.
- `conf/`     — buildroot defconfig, linux.config, busybox/uClibc configs.
- `output/`   — generated artifacts (git-ignored).
- `justfile`  — entry points.

## Commands

```
just fetch | patch | build | all | qemu-build | qemu-run | sd-card | clean | rebuild
```

Lint: `shellcheck scripts/*.sh && bash -n scripts/*.sh`

## Patch workflow

See [`workflow/create-new-patch.md`](workflow/create-new-patch.md).

1. Edit sources under `output/buildroot-2026.02/` (or `output/qemu-fork-src/` for QEMU).
2. `./scripts/gen-patches.sh "<subject>"` → new patch under `patches/{buildroot,adbd}/`.
   For QEMU: `./scripts/gen-patches.sh --qemu "<subject>"` → new patch under `patches/qemu/`.
3. Review. Never hand-write or edit existing patches directly.

> IMPORTANT: NEVER WRITE PATCH DIRECTLY, use script to generate patch.

**Avoid** this workflow:
1. Edit patch file directly=> it's very likely the patch later to be found flawed!
2. Clean the output dir=> it's energy-consuming to build from scratch.
3. Rebuild=> rebuild take 1 hour, please don't! 

Occasional rebuild is okay, but you need to avoid:
1. Obvious syntax error
2. Patch apply failure
3. missing patch that should be apply.

## Test workflow

- QEMU:
  1. check if your test require SD card(usually needed since onboard flash is small), if so, use real hardware.
- Real hardware:
  1. checking if SD card is inserted with `stat /dev/mmcblk0`.
  2. Ask user to insert SD card on host.
  3. Flash it.
  4. Ask user to swap it to the board
  5. Use openocd, st-link, `/dev/ttyACM0`(VCP) to test it.

## Conventions

- Patches are git `format-patch` style, numbered `NNNN-<slug>.patch`.
- `patches/buildroot/*` applied in place (`patch -p1 -N`);
  `patches/{adbd,gcc,linux,qemu}/*` copied into the buildroot tree by `02-patch-buildroot.sh`;
  `patches/qemu/*` applied to the QEMU fork source by `04-build-qemu.sh`.
