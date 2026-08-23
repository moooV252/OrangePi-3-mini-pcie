# armbian-integration

Everything that glues the patches, shim and boot chain into a standard Armbian
build.

## `orangepi3-pcie.sh` — Armbian extension (the important one)

Enable with `ENABLE_EXTENSIONS=orangepi3-pcie`. It:

1. **Pins the kernel** to the exact validated commit
   (`KERNELBRANCH=commit:2fe59671…`, 6.18.41) so `sunxi-6.18` advancing cannot
   silently turn the build into an untested configuration.
2. **Builds the EL2 shim** from `userpatches/sources/aw-el2-barebone/`
   (= [`../el2-shim/`](../el2-shim/) in this repo) into `hyp.bin`, into a fresh
   work directory on every build. It rejects any shim binary that contains
   FP/SIMD register operands — the code runs before FP access is enabled.
3. **Rebuilds TF-A** with `PRELOADED_BL33_BASE=0x4a000000` for the canonical
   TF-A → U-Boot → hyp.bin → Linux handoff.
4. **Configures U-Boot**: `CONFIG_SUNXI_H6_EL2_HYP=y`.
5. **Sets kernel options**: `PCIE_SUNXI_WRAPPED=y`, `PCI_MSI=y`.
6. Optionally installs boot-isolation diagnostic patches (see below).

### Diagnostic modes (all default OFF; leave off for normal builds)

| Env var | Effect |
|---|---|
| `ORANGEPI3_PCIE_DISABLE_PROBE=yes` | Installs `0002-disable-pcie-probe.patch`: DT node disabled but complete EL2 handoff retained — if such an image boots, the first paged PCIe access is provably the failing path |
| `ORANGEPI3_PCIE_SINGLE_CORE=yes` | Installs `0003-disable-secondary-cpus.patch` (primary-core isolation) |
| plus `DISABLE_STAGE2 / DISABLE_PSCI_TRAP / SKIP_SHIM_INIT / TABLES_ONLY / UBOOT_EL1_CONTROL` | Progressive shim/bypass isolations used during bring-up; guarded by cross-checks so invalid combinations fail the build |

The extension removes any stale diagnostic patch on every normal build, so a
prior diagnostic run can never contaminate a functional image.

## Build command (complete image)

```bash
./compile.sh build BOARD=orangepi3 BRANCH=current BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no DEST_LANG=en_US.UTF-8 KERNEL_CONFIGURE=no \
  PREFER_DOCKER=yes RELEASE=resolute SKIP_BOOTSPLASH=yes EXPERT=yes \
  ENABLE_EXTENSIONS=orangepi3-pcie
```

## Where each component goes in `userpatches/`

```
userpatches/
├── extensions/orangepi3-pcie.sh          ← this directory's .sh
├── kernel/archive/sunxi-6.18/*.patch     ← ../kernel-6.18/
├── u-boot/v2026.07-sunxi64/*.patch       ← ../u-boot/
└── sources/aw-el2-barebone/              ← ../el2-shim/
```
