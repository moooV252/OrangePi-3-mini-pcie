# el2-shim — aw-el2-barebone (vendored)

A minimal ARMv8 EL2 "hypervisor" stub for Allwinner SoCs, vendored from the
[aw-el2-barebone](https://github.com/anonymix007/aw-el2-barebone) project
(see LICENSE). Built by the Armbian extension into `hyp.bin`.

## Role in this project

On the Orange Pi 3's wrapped PCIe port, the controller bring-up must run at
EL2: the shim performs those accesses and installs stage-2 translation tables
so that Linux (EL1) sees a functioning port. Boot chain:

```
TF-A bl31 → U-Boot → hyp.bin (this code, @ 0x40010000) → Linux
```

## Build

Normally built automatically by `../armbian-integration/orangepi3-pcie.sh`
(fresh copy per build, plus a binary check rejecting any FP/SIMD instruction —
the shim runs before FP access is enabled).

Manual build:

```bash
make CROSS_COMPILE=aarch64-linux-gnu- clean all
# → el2-bb.bin (= hyp.bin), el2-bb.elf
```

Diagnostic build knobs (used during bring-up, not for production):
`DIAGNOSTIC_NO_STAGE2=1` (tables loaded, translation off),
`DIAGNOSTIC_NO_PSCI_TRAP=1`, `DIAGNOSTIC_SKIP_INIT=1`,
`DIAGNOSTIC_TABLES_ONLY=1`.

The original upstream README follows.

---


---

# Upstream README

Allwinner SoCs' 64-bit EL2 barebone
