# Linux 6.18.41 patch series (CURRENT — validated)

Eight patches for the Orange Pi 3 (Allwinner H6) that make the mini-PCIe port
work and an RTL8168F card in it reach gigabit speeds on mainline-based Armbian
(`BRANCH=current`, kernel commit `2fe596715f84…`, 6.18.41).

## Verify before use

```bash
sha256sum -c SHA256SUMS
grep -c "opi3_poll_ms\|hrtimer_setup\|netif_napi_add_weight" \
    0007-*.patch    # must be >= 8 (throughput fix present)
grep -c "rtl8169_missed_msi_recover\|rx_stall_polls" \
    0008-*.patch    # must be >= 6 (auto-recovery present)
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
| `0008-r8169-auto-recover-from-MSI-drop-RX-latch-on-H6.patch` | r8169/IRQ | Auto-recovery from MSI-drop RX latch: stall detector reads the live per-CPU counter (`dev_fetch_sw_netstats`; `rx_stall_polls`, default 3000 ≈ 3 s); recovery is renegotiate-first, chip reset only with `allow_chip_reset=1` (default off — SoC-wedge risk on H6). Soak-validated: 45 min sustained load, 0 in-window latches, 0 interventions |

## Module parameters after boot (0007 + 0008+0009)

```
/sys/module/r8169/parameters/poll_ms           # fallback poll period, ms (default 1)
/sys/module/r8169/parameters/rx_stall_polls    # stall threshold (default 3000; 0 = off)
/sys/module/r8169/parameters/reneg_check_polls # wait after renegotiate before escalation (default 2000)
/sys/module/r8169/parameters/allow_chip_reset  # permit full chip reset escalation (default N — unsafe on H6)
/sys/module/r8169/parameters/timer_only        # vendor moderation experiment (default N)
```

## Validated results (2026-08, flashed image)

- Link: 1 Gbit/s full duplex
- iperf3 single-stream: ~793–836 Mbit/s RX, ~756–764 Mbit/s TX
- Multi-stream: up to 873 Mbit/s RX / 824 TX
- MSI misses: ~1 per 25,000 polls, ≤1 ms impact each (~4 % sys CPU at full load)
- Auto-recovery: no false triggers in 25 min saturated iperf + hours idle;
  induced full-freeze latch recovered automatically within detection window
- Boot: zero-touch — all of the above baked into a standard Armbian image build
  with `ENABLE_EXTENSIONS=orangepi3-pcie`

## Post-build sanity checks on target

```bash
dmesg | grep "fallback armed"
# expect: ... missed-MSI fallback armed: period_ms=1 credit_ms=100 irq=NNN
ethtool enp1s0                       # 1000baseT/FD link
iperf3 -c <peer> -t 10               # >=700 Mbit/s both directions
```

## Known limitations (0009)

1. **Trickle-mode latch:** the stall detector counts *any* received packet as
   progress. A partial latch where occasional multicast/IPv6 frames still
   trickle in (while bulk/TCP RX is dead) resets the counter and will not
   trigger recovery.
2. **Idle-state flap cycle (soak finding):** when the link is idle, the
   endpoint can enter a repeating latch cycle — detector fires every ~7–15 s,
   PHY renegotiation restores the link in <10 s, and the cycle repeats for as
   long as the interface sits idle. Under sustained load this cycle does not
   occur (the 0007 fallback poller masks it). Benign for router uptime; visible
   as `ip link` flaps to monitoring tools. If flap noise matters, raise
   `rx_stall_polls` at load time (e.g. 6000–9000) at the cost of slower
   detection, or run a userspace watchdog instead of the in-driver ladder —
   but never both actors at once (they fight; see soak report §3.1).
3. **Chip-reset escalation is disabled by default** (`allow_chip_reset=N`) and
   must stay off on H6 until its SoC-wedge mechanism is captured on a serial
   console. Renegotiation covered 100 % of latches observed in soak testing.
