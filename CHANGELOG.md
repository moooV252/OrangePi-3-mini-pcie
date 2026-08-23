# Changelog

## 2026-08 — kernel-6.18 series, validated (current)

- Ported the wrapped-PCIe bring-up from the 5.7.4 lineage to Linux 6.18.41
  (Armbian `current`, kernel commit `2fe59671…`).
- Rewrote r8169 hardening for 6.18's driver: RX DMA shadow + clean stop,
  ASPM L0s/L1 off, conventional MSI only.
- Root-caused the throughput regression on 6.18: DWC MSI controller drops
  edge-triggered completions; jiffy quantization (`CONFIG_HZ=250`) made a
  naive fallback poller run at 4 ms → ~200 Mbit/s ceiling.
- Fix: hrtimer-driven missed-MSI fallback (`poll_ms` param, true sub-ms),
  NAPI weight 64→256. Result: ~793–873 Mbit/s RX / 756–824 TX, zero-touch boot.
- Full experiment log: `NOTE-20260823-r8169-6.18-throughput-fix.md` (in the
  private working tree; summarized in the top-level README).

## 2026-08 — kernel-5.7.4 lineage frozen (historical)

- Final experimental r8169 series of the 5.7.4 era: descriptor shadow failsafe,
  MSI-only forcing, freeze-dump diagnostics, vendor coalescing experiments,
  missed-MSI diagnostic fallback (v18). Baseline measured: 893/771 Mbit/s
  RX/TX, zero fallback hits in 57/57 frames.

## 2020-era origin (upstream communities)

- Wrapped-PCIe DTS approach and EL2-shim concept from the GermanAizek /
  ingamedeo OrangePi-3-H6-mainline trees; EL2 shim vendored from
  aw-el2-barebone.
