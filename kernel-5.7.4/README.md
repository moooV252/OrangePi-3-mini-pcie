# Linux 5.7.4 patch series (HISTORICAL — provenance only)

These patches are the **evolved form of the 2020-era 5.7.4 lineage** (GermanAizek /
ingamedeo OrangePi-3-H6-mainline work, further developed during this project's
reference phase). They are kept to document where the current 6.18 series came
from. **Do not apply them to a modern kernel tree** — `kernel-6.18/` supersedes
them completely.

## Files

- `0001–0010-*.patch` — the working 5.7.4 set: r8169 descriptor-DMA shadow
  failsafe (the anti-corruption idea that became today's 0003), EL2/U-Boot/DTS
  toolchain and clock patches, LED diagnostics.
- `r8169-experimental-v18/0001–0006` — the final experimental r8169 series of
  that era: shadow failsafe → force MSI-only → freeze-dump on first TX timeout →
  vendor coalescing experiments → **missed-MSI diagnostic fallback** (v18), the
  direct ancestor of the current kernel-6.18 `0007-r8169-missed-msi-fallback`.

## Lineage of ideas into kernel-6.18/

| 5.7.4 patch | Fate in 6.18 series |
|---|---|
| 0001 descriptor DMA shadow failsafe | rewritten as 0003 (RX shadow + clean stop) |
| 0002 force MSI only | becomes 0005 |
| vendor coalescing / timer-only experiments | falsified as a fix; survives only as optional flag in 0006 (default off) |
| v18 missed-MSI diagnostic fallback | productionized as 0007 with hrtimer + poll_ms param + NAPI weight 256 |
| DTS clock-rate patches | folded into 6.18 0001/0002 |

Known outcome on 5.7.4 hardware: link up, zero fallback hits in 57/57 test
frames, ~893/771 Mbit/s RX/TX baseline.
