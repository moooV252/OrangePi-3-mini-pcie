# Orange Pi 3 (H6) mini-PCIe: RTL8168F Gigabit Ethernet on mainline Linux

Bringing the Orange Pi 3's broken mini-PCIe port up on modern kernels — and getting
full wire speed out of an RTL8168F card in it.

**Result:** a zero-touch Armbian image for `BOARD=orangepi3` where the mini-PCIe
slot enumerates, the RTL8168F links at 1 Gbit/s, and iperf runs at **~790–870 Mbit/s**
per direction (single- and multi-stream), with a driver-level safety net that
contains the H6 PCIe controller's known failure modes.

| | Stock image | This stack |
|---|---|---|
| mini-PCIe enumeration | ✗ (port dead) | ✓ |
| Throughput (RX / TX) | — | 832–873 / 717–824 Mbit/s |
| Missed-MSI containment | — | ~1 event per 25 s of traffic, ≤1 ms impact |
| Boot | — | zero-touch (all fixes baked into the image) |

## What's actually wrong with this hardware

Three independent problems stack up:

1. **The H6 "wrapped" PCIe controller is not a normal DWC root complex.**
   Allwinner wired the DWC core behind vendor wrapper logic whose register
   interface and clock/reset sequencing differ from upstream expectations. On
   mainline U-Boot/Linux the port never enumerates without help. Worse, part of
   the bring-up must run at **EL2 (hypervisor level)**: certain controller
   registers misbehave when accessed from EL1 after Linux takes over. The boot
   chain therefore inserts a tiny EL2 shim that performs the critical accesses
   and sets up stage-2 translation before dropping to Linux.
2. **The endpoint (RTL8168F) occasionally corrupts descriptor rings or loses
   MSIs on this controller.** Two distinct eras, two distinct symptoms:
   - *5.7.4 era:* endpoint writes could replace complete RX/TX descriptors,
     and a naive driver fed those garbage DMA addresses into the arm64
     cache-maintenance code → fatal exception.
   - *6.18 era:* MSI delivery from the DWC MSI controller intermittently drops
     TxOK/RxOK completions. The driver latches `status=00000085` with no IRQ
     arriving; traffic stalls until something polls.
3. **The generic fallback mitigations are throughput-limited if done naively.**
   A timer-based poller quantized to the kernel jiffy (`CONFIG_HZ=250` → 4 ms
   floor) caps receive at ~200 Mbit/s regardless of what the wire can do.

## Repository layout

```
commit/
├── kernel-5.7.4/              Historical lineage (Linux 5.7.4, 2020-era BSP work)
│   ├── 0001–0010 …            Full patch set as used then (DTS clocks, LED
│   │                          diagnostics, toolchain fixes, r8169 shadow-DMA)
│   └── r8169-experimental-v18/
│       └── 0001–0006 …        Final experimental r8169 series of that era,
│                              culminating in the missed-MSI diagnostic fallback
│                              (the direct ancestor of today's patch 0007)
├── kernel-6.18/               CURRENT, VALIDATED series (Linux 6.18.41)
│   ├── 0001…0007-*.patch      The seven patches, in application order
│   └── SHA256SUMS             Integrity manifest — verify before use
├── u-boot/
│   └── 0001-sunxi-h6-load-pcie-el2-shim-before-uboot.patch
├── el2-shim/                  "aw-el2-barebone" — the EL2 hypervisor stub
│                              (C + ARM64 asm, builds to hyp.bin)
└── armbian-integration/
    ├── orangepi3-pcie.sh      Armbian extension: wires everything together
    └── 00xx-disable-*.patch   Optional boot-isolation diagnostics (off by default)
```

## History — which implementation came from which tree

| Era | Kernel | Source tree | What was taken |
|---|---|---|---|
| Origin | 3.10 vendor BSP | Allwinner/Longshan Android BSP | Proof it can work (>800 Mbit/s reported); entirely different PCIe/MSI path, nothing reusable directly |
| Reference | 5.7.4 | [GermanAizek](https://github.com/GermanAizek) + [ingamedeo](https://github.com/ingamedeo) OrangePi-3-H6-mainline trees | Wrapped-PCIE DTS approach, EL2-shim concept, first r8169 hardening. Our `kernel-5.7.4/` folder is the evolved form of this lineage |
| Current | 6.18.41 | mainline `sunxi` branch via Armbian (`KERNELBRANCH=commit:2fe59671…`) | Everything else rewritten/revalidated against the modern kernel: new wrapped-PCIe DTS patch, new r8169 series with hrtimer fallback |
| EL2 shim | — | [aw-el2-barebone](https://github.com/anonymix007/aw-el2-barebone) (Allwinner EL2 barebone) | Vendored under `el2-shim/`; built by the Armbian extension into `hyp.bin` |

The 5.7.4 patches are kept **for provenance only** — do not apply them to a modern
tree. The 6.18 series supersedes them completely but reuses their ideas:
descriptor shadowing → RX-only shadow + stop-on-corruption; MSI forcing → same;
vendor coalescing experiments → reduced to one optional timer-only flag;
missed-MSI diagnostic fallback → production missed-MSI fallback with hrtimer.

## Hypotheses tested (and verdicts)

| # | Hypothesis | Test | Verdict |
|---|---|---|---|
| H1 | Vendor interrupt moderation causes the slowdown | A/B: moderation off vs timer_only on — 355/130 vs 351/175 Mbit/s | ❌ Not the cause (kept as optional param anyway) |
| H2 | CPU frequency scaling throttles under load | Read `scaling_cur_freq` during iperf | ❌ All four cores pinned at 1.8 GHz |
| H3 | MAXI clock (PCIe data link width/clock) is mis-set | DTS assigns `maxi 200 MHz`, measured stable | ✓ Necessary (kept) |
| H4 | ASPM L0s/L1 breaks completions on this PHY | Disable endpoint L0s/L1 via patched config space | ✓ Stabilizing (kept) |
| H5 | Relaxed ordering corrupts DMA ordering | Disabled via config space write | Folded into stability work (kept) |
| H6 | MSI-X is the problem vector | Force conventional MSI only | ✓ Kept |
| H7 | Descriptor corruption is fatal because r8169 trusts hardware-owned descriptors | Shadow all mapped addresses, stop cleanly on mismatch | ✓ Eliminates the fatal exception class |
| H8 | Completions get lost because MSIs are dropped by the DWC MSI controller | dmesg shows `status=00000085 masked=00000005` latched with no IRQ; poller credits them | ✓ Confirmed → fallback is load-bearing |
| H9 | Vendor timer-only coalescing explains the regression | Same A/B as H1 | ❌ Falsified |
| H10 | The fallback poller period is the RX ceiling | 10 ms → ~355; 1 ms → ~620 Mbit/s | ✓ Confirmed |
| H11 | `poll_ms=1` gives 1 ms polling | Measured: `schedule_delayed_work()` quantizes to jiffies; `CONFIG_HZ=250` → **4 ms** floor | ⚠️ Surprising finding — led to H12 |
| H12 | NAPI budget × poll period = throughput cap | 64-desc budget × 250 polls/s ≈ 16 kpps ≈ 200 Mbit/s — matches observed plateau exactly | ✓ Arithmetic confirmed the mechanism |
| H13 | RPS spreading receive across CPUs helps | `rps_cpus=e`: RX 832→734 Mbit/s | ❌ IPI overhead exceeds gain on H6; keep off |
| H14 | SG/GSO enable helps TX | TX drops to ~690 Mbit/s | ❌ Reverted |
| H15 | TCP buffers/qdisc/BBR tuning closes the last gap | Swept buffers 16 MB, fq vs fq_codel | ➖ Neutral (BBR not built) |
| H16 | Remaining gap is the peer NIC (ASIX AX88179 USB), not the board | Board→two different peers cap identically; peer reports hundreds of retransmits under load while board TX errors ≈ 0 | ✓ Peer-side; jumbo frames are the next lever |

## How the final solution works

```
TF-A (bl31, PRELOADED_BL33_BASE=0x4a000000)
  └─> U-Boot (patched: loads hyp.bin before handoff)
        └─> EL2 shim (aw-el2-barebone, hyp.bin @ 0x40010000)
              • performs the EL2-critical wrapped-PCIe register accesses
              • installs stage-2 translation tables so Linux sees a sane port
              • drops to EL1
                └─> Linux 6.18.41
                      ├─ DTS: wrapped-PCIe node enabled, MAXI clock 200 MHz   [patch 0001, 0002]
                      └─ r8169 hardened for RTL8168F-on-H6:                  [patches 0003–0007]
                           03  RX DMA address shadowing + stop-on-corruption
                           04  endpoint ASPM L0s/L1 disabled
                           05  conventional MSI forced (no MSI-X)
                           06  vendor timer-only coalescing available (default off)
                           07  missed-MSI fallback:
                               • hrtimer-based poller (HRTIMER_MODE_REL_SOFT),
                                 true sub-ms period despite CONFIG_HZ=250
                               • module param `poll_ms` (default 1 ms)
                               • NAPI weight raised 64 → 256
                               • on a poll finding latched-but-unsignalled
                                 completions, credit them and re-arm quickly
```

The fallback costs ~4 % sys CPU at full gigabit and turns would-be multi-second
stalls into ≤1 ms blips (~1 per 25 s). Without it the port eventually hangs;
with a jiffy-quantized version it runs at ~200 Mbit/s; with hrtimer+weight-256
it reaches the numbers above.

### Why patch 0007 looks like overkill

It isn't defensive programming gone wild — every piece answers a measured
failure: the shadow checks answer descriptor corruption observed on real
hardware; the poller answers measured MSI loss; the hrtimer answers a measured
jiffy-quantization trap; the NAPI weight answers a measured arithmetic ceiling.
See `NOTE-20260823-r8169-6.18-throughput-fix.md` §10 for the full experiment log.

## Reproducing the build

Prereqs: a Linux host (or WSL) with `git` and Docker; nothing else — the script
handles the rest.

### One-shot script (recommended)

```bash
git clone <this repo>
cd commit
./build-orangepi3-image.sh            # builds in ~/armbian-build
# or: ./build-orangepi3-image.sh /path/to/existing/armbian-build
```

The script verifies patch integrity first, then installs every component into
the correct `userpatches/` location (kernel series → `kernel/archive/sunxi-6.18/`,
U-Boot patch → `u-boot/v2026.07-sunxi64/`, EL2 shim → `sources/aw-el2-barebone/`,
extension → `extensions/`), clears any stale diagnostic patches, and launches the
build. Image lands in `<armbian>/output/image/`.

### Manual steps

Prereqs: an Armbian build environment (Docker recommended) and this repo.

```bash
# 1. Verify patch integrity
cd kernel-6.18 && sha256sum -c SHA256SUMS

# 2. Place components into an Armbian build tree ("userpatches")
#    kernel-6.18/*.patch  -> userpatches/kernel/archive/sunxi-6.18/
#    u-boot/*.patch       -> userpatches/u-boot/v2026.07-sunxi64/
#    el2-shim/            -> userpatches/sources/aw-el2-barebone/
#    armbian-integration/orangepi3-pcie.sh -> userpatches/extensions/

# 3. Build
./compile.sh build BOARD=orangepi3 BRANCH=current BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no DEST_LANG=en_US.UTF-8 KERNEL_CONFIGURE=no \
  PREFER_DOCKER=yes RELEASE=resolute SKIP_BOOTSPLASH=yes EXPERT=yes \
  ENABLE_EXTENSIONS=orangepi3-pcie

# 4. Flash, boot, verify
dmesg | grep "fallback armed"     # expect: period_ms=1 credit_ms=100 irq=NNN
iperf3 -c <peer> -t 10            # expect ≥700 Mbit/s each direction
```

The extension pins `KERNELBRANCH` to the exact validated kernel commit, builds
the EL2 shim fresh on every build (rejecting any binary that uses FP/SIMD
registers — the shim runs before FP is enabled), rebuilds TF-A with the right
BL33 base, and enables the wrapped-PCIe + MSI kernel options.

Optional boot-isolation diagnostics (for boards without serial console):
`ORANGEPI3_PCIE_DISABLE_PROBE=yes` produces an image that boots only if the
first paged PCIe access is the failing path; see `armbian-integration/`.

## Results summary

| Metric | Value |
|---|---|
| Link | 1 Gbit/s full duplex, flow-control rx/tx |
| Single-stream iperf3 | 793–836 Mbit/s RX, 756–764 Mbit/s TX |
| Multi-stream (-P 4–8) | up to 873 Mbit/s RX, 806–824 Mbit/s TX |
| MSI misses caught by fallback | ~1 per 25,000 polls (≤1 ms impact each) |
| CPU idle at full RX | ~96 % |
| Known remaining bottleneck | peer-side (USB NIC) receive path, not the board |

## License & credits

- Kernel patches: GPL-2.0 (Linux kernel licensing applies).
- EL2 shim: see `el2-shim/LICENSE` (vendored from aw-el2-barebone).
- Built on the work of the GermanAizek and ingamedeo mainline-H6 communities,
  the aw-el2-barebone author(s), and the Armbian project.

## Status

Working and validated on hardware (2026-08). Open items and the full experiment
chronology live in the notes referenced above; the deepest remaining unknown is
*why* the 6.18 DWC MSI path drops edge-triggered interrupts where 5.7.4 did not
— the fallback contains it, but doesn't explain it.
