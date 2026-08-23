# U-Boot patch (v2026.07 sunxi64)

`0001-sunxi-h6-load-pcie-el2-shim-before-uboot.patch`

Makes U-Boot load and jump through the EL2 shim (`hyp.bin`, built from
[`../el2-shim/`](../el2-shim/)) **before** handing control to the Linux kernel.

Why: on the H6 wrapped PCIe port, the critical controller bring-up accesses must
happen at EL2. After Linux starts (EL1) it is too late — the port never
enumerates. The chain is therefore:

```
TF-A bl31 → U-Boot → hyp.bin (EL2 shim @ 0x40010000) → Linux (EL1)
```

The Armbian extension (`armbian-integration/orangepi3-pcie.sh`) also rebuilds
TF-A with `PRELOADED_BL33_BASE=0x4a000000` so bl31 places U-Boot where the shim
handoff expects it, and sets `CONFIG_SUNXI_H6_EL2_HYP=y` in the U-Boot config.
All of this happens automatically in an Armbian build with
`ENABLE_EXTENSIONS=orangepi3-pcie`; there is no manual step.
