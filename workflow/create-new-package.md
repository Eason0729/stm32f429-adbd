# How to add a new buildroot package

This project uses buildroot patches to add custom packages. Follow this workflow to add a new one.

## Steps

### 1. Create package files under the buildroot tree

```
output/buildroot-2026.02/package/<name>/
├── Config.in          # BR2_PACKAGE_<NAME> bool config
├── <name>.mk          # Build rules (generic-package, local source)
└── <name>.c           # Source file (if single-file C program)
```

For a single-file C program using `generic-package` + local source:

**Config.in:**
```
config BR2_PACKAGE_<NAME>
	bool "<name>"
	help
	  Description of what this package does.
```

**`<name>.mk`:**
```make
################################################################################
#
# <name>
#
################################################################################

<NAME>_VERSION = 1.0
<NAME>_SITE = $(<NAME>_PKGDIR)
<NAME>_SITE_METHOD = local
<NAME>_LICENSE = GPL-2.0

define <NAME>_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -o $(@D)/<name> $(@D)/<name>.c
endef

define <NAME>_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/<name> $(TARGET_DIR)/usr/bin/<name>
endef

$(eval $(generic-package))
```

### 2. Wire into buildroot menus

Edit `output/buildroot-2026.02/package/Config.in`:

```diff
+menu "USB gadgets"
+	source "package/<name>/Config.in"
+endmenu
+
 menu "Graphic libraries and applications (graphic/text)"
```

### 3. Enable in defconfig

Add to `conf/buildroot.config`:

```diff
+BR2_PACKAGE_<NAME>=y
```

This is applied automatically by `02-patch-buildroot.sh` (copies `conf/buildroot.config` → `configs/stm32f429_disco_xip_defconfig`).

### 4. Generate patch

```sh
./scripts/gen-patches.sh "add-<name>-package"
```

A new patch appears under `patches/buildroot/NNNN-add-<name>-package.patch`.

### 5. Clean up

- Delete any superseded top-level files (they now live in the patchset)
- Keep a working copy at the top-level only if you plan to edit it further and regenerate the patch later

## Reference

- See `echo_gadget` (patches/buildroot/0017) as a worked example
- For multi-file or complex builds, use git-sourced packages (see `adbd` as reference)
