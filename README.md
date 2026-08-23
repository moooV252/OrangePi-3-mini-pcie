# Orange Pi 3 (H6) mini-PCIe: RTL8168F gigabit Ethernet on mainline Linux

This project brings the Orange Pi 3 mini-PCIe port up on modern kernels and gets full wire speed out of an RTL8168F card in it. The result is a zero-touch Armbian image for BOARD=orangepi3. The mini-PCIe slot enumerates, the RTL8168F links at 1 Gbit/s, and iperf runs at 790 to 870 Mbit/s per direction in single and multi-stream tests. A driver-level safety net contains the known failure modes of the H6 PCIe controller.

In the stock image, the port is dead and mini-PCIe enumeration fails. In this stack, enumeration succeeds. Throughput reaches 832 to 949 Mbit/s RX and 717 to 949 Mbit/s TX. Missed-MSI containment happens about once every 25 s of traffic, with 1 ms or less impact. The boot is zero-touch, with all fixes baked into the image.



## What is actually wrong with this hardware

The hardware has three independent problems.

1. The H6 "wrapped" PCIe controller is not a normal DWC root complex. Allwinner wired the DWC core behind vendor wrapper logic whose register interface and clock/reset sequencing differ from upstream expectations. On mainline U-Boot/Linux the port never enumerates without help. Part of the bring-up must run at EL2, the hypervisor level. Certain controller registers misbehave when accessed from EL1 after Linux takes over. The boot chain inserts a tiny EL2 shim that performs the critical accesses and sets up stage-2 translation before dropping to Linux.
2. The endpoint, RTL8168F, occasionally corrupts descriptor rings or loses MSIs on this controller. In the 5.7.4 era, endpoint writes could replace complete RX/TX descriptors, and a naive driver fed those garbage DMA addresses into the arm64 cache-maintenance code, causing a fatal exception. In the 6.18 era, MSI delivery from the DWC MSI controller intermittently drops TxOK/RxOK completions. The driver latches status=00000085 with no IRQ arriving, and traffic stalls until something polls.
3. The generic fallback mitigations are throughput-limited if done naively. A timer-based poller quantized to the kernel jiffy, CONFIG_HZ=250, gives a 4 ms floor and caps receive at about 200 Mbit/s, regardless of what the wire can do.

## How the final solution works

1. TF-A uses bl31 with PRELOADED_BL33_BASE=0x4a000000.
2. U-Boot is patched to load hyp.bin before handoff.
3. The EL2 shim is aw-el2-barebone. The hyp.bin image sits at 0x40010000. It performs the EL2-critical wrapped-PCIe register accesses, installs stage-2 translation tables so Linux sees a sane port, and drops to EL1.
4. Linux 6.18.41 starts with the wrapped-PCIe node enabled in the DTS and MAXI clock set to 200 MHz, using patches 0001 and 0002.

The r8169 driver is hardened for RTL8168F on H6 using patches 0003 to 0007:

1. Patch 0003 adds RX DMA address shadowing and stop-on-corruption.
2. Patch 0004 disables endpoint ASPM L0s/L1.
3. Patch 0005 forces conventional MSI and does not use MSI-X.
4. Patch 0006 makes vendor timer-only coalescing available, default off.
5. Patch 0007 adds a missed-MSI fallback. It uses an hrtimer-based poller with HRTIMER_MODE_REL_SOFT, which gives a true sub-ms period despite CONFIG_HZ=250. It has a module parameter poll_ms with default 1 ms. It raises NAPI weight from 64 to 256. When a poll finds latched-but-unsignalled completions, the driver credits them and re-arms quickly.

The fallback costs about 4% sys CPU at full gigabit and turns would-be multi-second stalls into 1 ms or less blips, about 1 per 25 s. Without it the port eventually hangs. With a jiffy-quantized version it runs at about 200 Mbit/s. With hrtimer and NAPI weight 256 it reaches the numbers above.


## Hypotheses tested and verdicts

1. Vendor interrupt moderation causes the slowdown. Test: A/B with moderation off versus timer_only on, 355/130 versus 351/175 Mbit/s. Verdict: no, not the cause, kept as optional param anyway.
2. CPU frequency scaling throttles under load. Test: read scaling_cur_freq during iperf. Verdict: no, all four cores pinned at 1.8 GHz.
3. MAXI clock, the PCIe data link width/clock, is mis-set. Test: DTS assigns maxi 200 MHz, measured stable. Verdict: yes, necessary, kept.
4. ASPM L0s/L1 breaks completions on this PHY. Test: disable endpoint L0s/L1 via patched config space. Verdict: yes, stabilizing, kept.
5. Relaxed ordering corrupts DMA ordering. Test: disabled via config space write. Verdict: folded into stability work, kept.
6. MSI-X is the problem vector. Test: force conventional MSI only. Verdict: kept.
7. Descriptor corruption is fatal because r8169 trusts hardware-owned descriptors. Test: shadow all mapped addresses, stop cleanly on mismatch. Verdict: eliminates the fatal exception class.
8. Completions get lost because MSIs are dropped by the DWC MSI controller. Test: dmesg shows status=00000085 masked=00000005 latched with no IRQ, and the poller credits them. Verdict: confirmed, the fallback is load-bearing.
9. Vendor timer-only coalescing explains the regression. Test: same A/B as H1. Verdict: falsified.
10. The fallback poller period is the RX ceiling. Test: 10 ms gives about 355 Mbit/s, 1 ms gives about 620 Mbit/s. Verdict: confirmed.
11. poll_ms=1 gives 1 ms polling. Test: measured schedule_delayed_work() quantizes to jiffies, and CONFIG_HZ=250 gives a 4 ms floor. Verdict: surprising finding, led to H12.
12. NAPI budget times poll period equals the throughput cap. Test: 64 descriptor budget times 250 polls per second, about 16 kpps, about 200 Mbit/s, matches the observed plateau exactly. Verdict: arithmetic confirmed the mechanism.
13. RPS spreading receive across CPUs helps. Test: rps_cpus=e, RX 832 to 734 Mbit/s. Verdict: no, IPI overhead exceeds gain on H6, keep off.
14. SG/GSO enable helps TX. Test: TX drops to about 690 Mbit/s. Verdict: reverted.
15. TCP buffers/qdisc/BBR tuning closes the last gap. Test: swept buffers 16 MB, fq versus fq_codel. Verdict: neutral, BBR not built.
16. The remaining gap is the peer NIC, ASIX AX88179 USB, not the board. Test: the board caps identically to two different peers, the peer reports hundreds of retransmits under load, and board TX errors are about 0. Verdict: peer-side, jumbo frames are the next lever.

## Why patch 0007 looks like overkill

It is not defensive programming gone wild. Each piece answers a measured failure. The shadow checks answer descriptor corruption observed on real hardware. The poller answers measured MSI loss. The hrtimer answers a measured jiffy-quantization trap. The NAPI weight answers a measured arithmetic ceiling.

## Status

The work is working and validated on hardware as of 2026-08. Open items and the full experiment chronology live in the notes referenced above. The deepest remaining unknown is why the 6.18 DWC MSI path drops edge-triggered interrupts where 5.7.4 did not. The fallback contains the problem, but it does not explain it.


## Iperf3 stats, best run against a Windows peer

```text
root@orangepi3:~# iperf3 -s
-----------------------------------------------------------
Server listening on 5201 (test #1)
-----------------------------------------------------------
Accepted connection from 192.168.1.3, port 62655
[  5] local 192.168.1.50 port 5201 connected to 192.168.1.3 port 62656
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-1.00   sec   113 MBytes   946 Mbits/sec
[  5]   1.00-2.00   sec   113 MBytes   950 Mbits/sec
[  5]   2.00-3.00   sec   113 MBytes   949 Mbits/sec
[  5]   3.00-4.00   sec   113 MBytes   949 Mbits/sec
[  5]   4.00-5.00   sec   113 MBytes   950 Mbits/sec
[  5]   5.00-6.00   sec   113 MBytes   949 Mbits/sec
[  5]   6.00-7.00   sec   113 MBytes   949 Mbits/sec
[  5]   7.00-8.00   sec   113 MBytes   949 Mbits/sec
[  5]   8.00-9.00   sec   113 MBytes   950 Mbits/sec
[  5]   9.00-10.00  sec   113 MBytes   949 Mbits/sec
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  1.10 GBytes   949 Mbits/sec                  receiver
-----------------------------------------------------------
Server listening on 5201 (test #2)
-----------------------------------------------------------
Accepted connection from 192.168.1.3, port 62661
[  5] local 192.168.1.50 port 5201 connected to 192.168.1.3 port 62662
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec   112 MBytes   938 Mbits/sec    0    242 KBytes
[  5]   1.00-2.00   sec   113 MBytes   945 Mbits/sec    0    282 KBytes
[  5]   2.00-3.00   sec   113 MBytes   951 Mbits/sec    0    301 KBytes
[  5]   3.00-4.00   sec   113 MBytes   948 Mbits/sec    0    322 KBytes
[  5]   4.00-5.00   sec   113 MBytes   951 Mbits/sec    0    354 KBytes
[  5]   5.00-6.00   sec   114 MBytes   954 Mbits/sec    0    394 KBytes
[  5]   6.00-7.00   sec   113 MBytes   951 Mbits/sec    0    413 KBytes
[  5]   7.00-8.00   sec   113 MBytes   946 Mbits/sec    0    432 KBytes
[  5]   8.00-9.00   sec   113 MBytes   949 Mbits/sec    0    456 KBytes
[  5]   9.00-10.00  sec   113 MBytes   950 Mbits/sec   30    402 KBytes
[  5]  10.00-10.01  sec  1.38 MBytes  1.30 Gbits/sec    0    402 KBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.01  sec  1.11 GBytes   949 Mbits/sec   30            sender
```


## Results summary

Link: 1 Gbit/s full duplex, flow-control rx/tx.

Single-stream iperf3: 793 to 836 Mbit/s RX, 756 to 764 Mbit/s TX.

Multi-stream iperf3 with -P 4 to 8: up to 873 Mbit/s RX, 806 to 824 Mbit/s TX.

MSI misses caught by fallback: about 1 per 25,000 polls, with 1 ms or less impact each.

CPU idle at full RX: about 96%.

Known remaining bottleneck: peer-side USB NIC receive path, not the board.

## One-shot script, recommended

```bash
git clone <this repo>
cd commit
./build-orangepi3-image.sh            # builds in ~/armbian-build
# or: ./build-orangepi3-image.sh /path/to/existing/armbian-build
```

The script verifies patch integrity first. Then it installs every component into the correct userpatches/ location: kernel series to kernel/archive/sunxi-6.18/, U-Boot patch to u-boot/v2026.07-sunxi64/, EL2 shim to sources/aw-el2-barebone/, extension to extensions/. It clears any stale diagnostic patches and launches the build. The image lands in <armbian>/output/image/.

## Manual steps

Prereqs: an Armbian build environment, Docker recommended, and this repo.

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
iperf3 -c <peer> -t 10            # expect >=700 Mbit/s each direction
```

The extension pins KERNELBRANCH to the exact validated kernel commit. It builds the EL2 shim fresh on every build, rejecting any binary that uses FP/SIMD registers because the shim runs before FP is enabled. It rebuilds TF-A with the right BL33 base and enables the wrapped-PCIe and MSI kernel options.

Optional boot-isolation diagnostics exist for boards without serial console. Setting ORANGEPI3_PCIE_DISABLE_PROBE=yes produces an image that boots only if the first paged PCIe access is the failing path. See armbian-integration/.

## History, which implementation came from which tree

Origin: kernel 3.10 vendor BSP. Source tree is Allwinner/Longshan Android BSP. What was taken: proof it can work, with >800 Mbit/s reported. It uses an entirely different PCIe/MSI path, and nothing is reusable directly.

Reference: kernel 5.7.4. Source trees are [GermanAizek](https://github.com/GermanAizek/OrangePi-3-H6-mainline) and [ingamedeo](https://github.com/ingamedeo/orangepi3-h6-mainline), the OrangePi-3-H6-mainline trees. What was taken: wrapped-PCIE DTS approach, EL2-shim concept, first r8169 hardening. Our kernel-5.7.4 folder is the evolved form of this lineage.

Current: kernel 6.18.41. Source tree is mainline sunxi branch via Armbian with KERNELBRANCH=commit:2fe59671... What was taken: everything else rewritten and revalidated against the modern kernel, including a new wrapped-PCIe DTS patch and a new r8169 series with hrtimer fallback.

EL2 shim: kernel not applicable. Source tree is [aw-el2-barebone](https://github.com/anonymix007/aw-el2-barebone), the Allwinner EL2 barebone. What was taken: vendored under el2-shim/ and built by the Armbian extension into hyp.bin.

The 5.7.4 patches are kept for provenance only. Do not apply them to a modern tree. The 6.18 series supersedes them completely, but it reuses their ideas. Descriptor shadowing becomes RX-only shadow plus stop-on-corruption. MSI forcing remains. Vendor coalescing experiments reduce to one optional timer-only flag. The missed-MSI diagnostic fallback becomes a production missed-MSI fallback with hrtimer.

## Repository layout

```text
commit/
  kernel-5.7.4/
    Historical lineage, Linux 5.7.4, 2020-era BSP work
    0001 to 0010: full patch set as used then, covering DTS clocks, LED diagnostics, toolchain fixes, r8169 shadow-DMA
    r8169-experimental-v18/
      0001 to 0006: final experimental r8169 series of that era, ending with the missed-MSI diagnostic fallback that is the direct ancestor of today's patch 0007
  kernel-6.18/
    Current, validated series, Linux 6.18.41
    0001 to 0007-*.patch: the seven patches, in application order
    SHA256SUMS: integrity manifest, verify before use
  u-boot/
    0001-sunxi-h6-load-pcie-el2-shim-before-uboot.patch
  el2-shim/
    aw-el2-barebone, the EL2 hypervisor stub, C plus ARM64 asm, builds to hyp.bin
  armbian-integration/
    orangepi3-pcie.sh: Armbian extension that wires everything together
    00xx-disable-*.patch: optional boot-isolation diagnostics, off by default
```

## Reproducing the build

Prereqs: a Linux host or WSL with git and Docker. That is all. The script handles the rest.

## License and credits

Kernel patches: GPL-2.0, Linux kernel licensing applies.

EL2 shim: see el2-shim/LICENSE, vendored from aw-el2-barebone.

This work is built on the work of the GermanAizek and ingamedeo mainline-H6 communities, the aw-el2-barebone author(s), and the Armbian project.