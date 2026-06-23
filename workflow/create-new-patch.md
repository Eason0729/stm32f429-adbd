# Create a New Patch

The repo keeps its customizations to upstream sources as ordered patch files
under `patches/`, grouped by target:

| Directory         | Applied to                                  | How                                              |
|-------------------|---------------------------------------------|--------------------------------------------------|
| `patches/buildroot/` | buildroot source tree (in place)          | `patch -p1` during `02-patch-buildroot.sh`      |
| `patches/adbd/`      | `package/adbd/` inside buildroot          | copied into the package dir (buildroot applies them) |
| `patches/gcc/`       | `package/gcc/14.3.0/` inside buildroot    | copied into the package dir                      |
| `patches/linux/`     | kernel source at kernel build time        | copied to `board/.../patches/linux/`            |
| `patches/qemu/`      | QEMU fork source tree (`output/qemu-fork-src/`) | `patch -p1` during `04-build-qemu.sh`      |

## Workflow

### Buildroot / adbd / gcc / linux patches

1. **Edit source files directly** under `output/buildroot-2026.02/`.
   - For buildroot-tree changes (e.g. `linux/linux.mk`, `Config.in`), edit in place.
   - For adbd package changes, edit under `output/buildroot-2026.02/package/adbd/`.
2. **Generate the patch**:

   ```sh
   ./scripts/gen-patches.sh "<short subject>"
   ```

   The script:
   - rebuilds a pristine baseline by re-applying the current `patches/buildroot/*`
     and re-copying `patches/{adbd,gcc,linux}/*` + conf files (mirroring
     `02-patch-buildroot.sh`),
   - diffs your modified `output/buildroot-2026.02/` against that baseline,
   - writes a new numbered git-format-patch file under `patches/buildroot/`
     and/or `patches/adbd/` (only the scopes that changed).

3. **Review the new patch**:

   ```sh
   git diff --no-index /dev/null patches/<scope>/<new-number>-*.patch   # or just open it
   ```

   Verify it contains *only* your intended changes. If the patch also captures
   unrelated lines, your `output/buildroot-2026.02/` tree was out of sync —
   run `just clean && just patch` to reset, re-apply your edits, and try again.

### QEMU fork patches

1. **Edit source files directly** under `output/qemu-fork-src/`
   (populated by `just qemu-build` / `scripts/04-build-qemu.sh`).
2. **Generate the patch**:

   ```sh
   ./scripts/gen-patches.sh --qemu "<short subject>"
   ```

   The script:
   - clones a fresh copy of the QEMU fork source,
   - applies existing `patches/qemu/*` to build the baseline,
   - diffs your modified `output/qemu-fork-src/` against that baseline,
   - writes a new numbered git-format-patch file under `patches/qemu/`.

3. **Review the new patch** (same as buildroot patches).

## Notes

- Patches are numbered `NNNN-<slug>.patch`; the slug is derived from the
  subject you pass (`gen-patches.sh "<subject>"`).
- adbd-package changes are emitted into `patches/adbd/` (separate from
  `patches/buildroot/`), because buildroot applies them as package patches
  rather than as source-tree patches.
- QEMU patches use `--qemu` flag: `gen-patches.sh --qemu "<subject>"`.
- Re-running `gen-patches.sh` with no further edits reports
  "No changes detected." — the new patch is now part of the baseline.
- After generating a patch, the change is permanent: the next `just patch`
  (or `just qemu-build`) will re-apply it. Do not re-apply manually.

## Example: adding a noMMU build flag to adbd

```sh
# 1. edit the adbd sources inside buildroot
$EDITOR output/buildroot-2026.02/package/adbd/adb/Makefile
# ... and adb.cpp, shell_service.cpp, configure, include.mk ...

# 2. generate the patch (writes patches/adbd/0001-adbd-noMMU.patch)
./scripts/gen-patches.sh "adbd noMMU"

# 3. inspect
less patches/adbd/0001-adbd-noMMU.patch
```

## Example: adding SPI4 MMC SD card to the QEMU board model

```sh
# 1. edit the QEMU board source
$EDITOR output/qemu-fork-src/hw/arm/stm32f429-discovery.c

# 2. generate the patch (writes patches/qemu/0001-add-spi4-mmc.patch)
./scripts/gen-patches.sh --qemu "add-spi4-mmc"

# 3. inspect
less patches/qemu/0001-add-spi4-mmc.patch

# 4. rebuild QEMU with the new patch
just qemu-build
```