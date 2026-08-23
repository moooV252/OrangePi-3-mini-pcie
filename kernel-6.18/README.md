# Linux 6.18.41 patch series (CURRENT — validated)

Seven patches for the Orange Pi 3 (Allwinner H6) that make the mini-PCIe port
work and an RTL8168F card in it reach gigabit speeds on mainline-based Armbian
(`BRANCH=current`, kernel commit `2fe596715f84…`, 6.18.41).

## Verify before use

```bash
sha256sum -c SHA256SUMS
grep -c "opi3_poll_ms\|hrtimer_setup\|netif_napi_add_weight" \
    0007-r8169-missed-msi-fallback-for-rtl8168f.patch   # must be ≥ 8
```

## Application order (Armbian applies them automatically in filename order)

| Patch | Layer | Purpose |
|---|---|---|
| `0001-arm64-allwinner-h6-add-wrapped-pcie-support.patch` | DTS/platform | Enable the H6 wrapped PCIe root complex node |
| `0002-arm64-dts-h6-assign-pcie-maxi-200mhz.patch` | DTS/clocks | Pin the MAXI clock at 200 MHz |
| `0003-r8169-shadow-rx-dma-addresses-and-stop-on-corruption.patch` | r8169 | Shadow RX DMA addresses; validate completions against shadows; stop cleanly instead of feeding corrupt addresses to the DMA API |
| `0004-r8169-disable-endpoint-aspm-l0s-l1.patch` | r8169/PCIe | Disable endpoint ASPM L0s/L1 (completion corruption on this PHY) |
| `0005-r8169-conventional-msi-only-for-rtl8168f.patch` | r8169/MSI | Force conventional MSI, never MSI-X |
| `0006-r8169-vendor-timer-only-coalescing-for-rtl8168f.patch` | r8169 | Optional vendor timer-only moderation mode (`timer_only=1`); **default off** — A/B-tested as performance-neutral |
| `0007-r8169-missed-msi-fallback-for-rtl8168f.patch` | r8169/IRQ | The throughput fix: hrtimer-driven missed-MSI fallback poller (`poll_ms`, default 1 ms — true sub-ms despite CONFIG_HZ=250) + NAPI weight 64→256 |

## Validated results (2026-08, flashed image)

- Link: 1 Gbit/s full duplex
- iperf3 single-stream: ~793–836 Mbit/s RX, ~756–764 Mbit/s TX
- Multi-stream: up to 873 Mbit/s RX / 824 TX
- MSI misses: ~1 per 25,000 polls, ≤1 ms impact each (~4 % sys CPU at full load)
- Boot: zero-touch — all of the above baked into a standard Armbian image build
  with `ENABLE_EXTENSIONS=orangepi3-pcie`

## Post-build sanity checks on target

```bash
dmesg | grep "fallback armed"
# expect: ... missed-MSI fallback armed: period_ms=1 credit_ms=100 irq=NNN
ethtool enp1s0                       # 1000baseT/FD link
iperf3 -c <peer> -t 10               # ≥700 Mbit/s both directions
```
