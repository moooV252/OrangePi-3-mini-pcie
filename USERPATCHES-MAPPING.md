# Copy this repo into an Armbian build tree — mapping

This repository is laid out by *component*, not by Armbian's `userpatches/`
layout. Mapping when preparing a build:

| This repo | Armbian `userpatches/` |
|---|---|
| `kernel-6.18/*.patch`, `SHA256SUMS` | `userpatches/kernel/archive/sunxi-6.18/` |
| `u-boot/0001-*.patch` | `userpatches/u-boot/v2026.07-sunxi64/` |
| `el2-shim/*` | `userpatches/sources/aw-el2-barebone/` |
| `armbian-integration/orangepi3-pcie.sh` | `userpatches/extensions/` |
| `armbian-integration/0002,0003-*.patch` | `userpatches/sources/orangepi3-pcie-diagnostics/` (only needed for the optional diagnostics) |

Then build with `ENABLE_EXTENSIONS=orangepi3-pcie` (see top-level README).
