`stm32f429-adbd` — cross-builds a minimal noMMU Linux + adbd for the
STM32F429I-DISCO board using buildroot 2026.02.

## Skill

- stm32 skill(for reference manual RM0090)
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

## Conventions

- Patches are git `format-patch` style, numbered `NNNN-<slug>.patch`.
- `patches/buildroot/*` applied in place (`patch -p1 -N`);
  `patches/{adbd,gcc,linux,qemu}/*` copied into the buildroot tree by `02-patch-buildroot.sh`;
  `patches/qemu/*` applied to the QEMU fork source by `04-build-qemu.sh`.
