#!/usr/bin/env bash
#
# build-orangepi3-image.sh — prepare an Armbian build tree with the
# Orange Pi 3 H6 mini-PCIe patches and launch a full image build.
#
# What it does:
#   1. Verifies patch integrity (SHA256SUMS) before touching anything.
#   2. Clones/updates the Armbian build repo (or uses an existing one).
#   3. Installs every component into the correct userpatches/ location:
#        kernel-6.18/*.patch      -> userpatches/kernel/archive/sunxi-6.18/
#        u-boot/*.patch           -> userpatches/u-boot/v2026.07-sunxi64/
#        el2-shim/*               -> userpatches/sources/aw-el2-barebone/
#        armbian-integration/*.sh -> userpatches/extensions/orangepi3-pcie.sh
#   4. Removes any stale diagnostic patches (so a prior diagnostic run can
#      never contaminate this functional image).
#   5. Launches compile.sh with ENABLE_EXTENSIONS=orangepi3-pcie.
#
# Usage:
#   ./build-orangepi3-image.sh /path/to/armbian-build [output-dir]
#
# If the path does not exist, the script clones
# https://github.com/armbian/build into it first.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARMBIAN="${1:-$HOME/armbian-build}"
OUTDIR="${2:-$ARMBIAN/output/image}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- sanity ---

log "Verifying kernel patch integrity"
( cd "$REPO_DIR/kernel-6.18" && sha256sum -c SHA256SUMS ) \
    || die "kernel-6.18 patches failed integrity check"

MARKERS="$(grep -c 'opi3_poll_ms\|hrtimer_setup\|netif_napi_add_weight' \
    "$REPO_DIR/kernel-6.18/0007-r8169-missed-msi-fallback-for-rtl8168f.patch" || true)"
[ "${MARKERS:-0}" -ge 8 ] \
    || die "0007 is missing throughput-fix markers (got $MARKERS, need >= 8) — stale copy?"

for f in "$REPO_DIR/u-boot/0001-sunxi-h6-load-pcie-el2-shim-before-uboot.patch" \
         "$REPO_DIR/armbian-integration/orangepi3-pcie.sh" \
         "$REPO_DIR/el2-shim/Makefile" \
         "$REPO_DIR/el2-shim/include/h6.h"; do
    [ -f "$f" ] || die "missing required file: $f"
done

# ------------------------------------------------------------ armbian tree ---

if [ ! -d "$ARMBIAN" ]; then
    log "Cloning armbian/build into $ARMBIAN"
    git clone --depth=1 https://github.com/armbian/build "$ARMBIAN"
elif [ ! -f "$ARMBIAN/compile.sh" ]; then
    die "$ARMBIAN exists but has no compile.sh — pass the correct path"
fi

USERPATCHES="$ARMBIAN/userpatches"
mkdir -p "$USERPATCHES/extensions" \
         "$USERPATCHES/sources" \
         "$USERPATCHES/kernel/archive/sunxi-6.18" \
         "$USERPATCHES/u-boot/v2026.07-sunxi64"

# --------------------------------------------------------- install pieces ---

log "Installing kernel patch series (sunxi-6.18)"
install -m 0644 "$REPO_DIR"/kernel-6.18/0*.patch \
                "$REPO_DIR/kernel-6.18/SHA256SUMS" \
                "$USERPATCHES/kernel/archive/sunxi-6.18/"
NPATCHES="$(ls "$USERPATCHES/kernel/archive/sunxi-6.18/"*.patch | wc -l)"
[ "$NPATCHES" -eq 7 ] || die "expected exactly 7 kernel patches in place, found $NPATCHES"

log "Installing U-Boot patch (v2026.07 sunxi64)"
rm -f "$USERPATCHES"/u-boot/v2026.07-sunxi64/*.patch
install -m 0644 "$REPO_DIR"/u-boot/*.patch "$USERPATCHES/u-boot/v2026.07-sunxi64/"

log "Installing EL2 shim source (aw-el2-barebone)"
SHIM_SRC="$USERPATCHES/sources/aw-el2-barebone"
rm -rf "$SHIM_SRC"
cp -a "$REPO_DIR/el2-shim" "$SHIM_SRC"
[ -f "$SHIM_SRC/Makefile" ] && [ -f "$SHIM_SRC/include/h6.h" ] \
    || die "EL2 shim source incomplete after copy"

log "Installing Armbian extension (orangepi3-pcie)"
install -m 0755 "$REPO_DIR/armbian-integration/orangepi3-pcie.sh" \
                "$USERPATCHES/extensions/orangepi3-pcie.sh"

log "Clearing any stale diagnostic kernel patches"
rm -f "$USERPATCHES/kernel/archive/sunxi-6.18/"999*-diagnostic.patch

log "userpatches layout:"
find "$USERPATCHES" -type f | sed "s|$USERPATCHES/|    |" | sort

# ------------------------------------------------------------------ build ---

log "Starting Armbian image build (this can take 1-2 h; log: build.log)"
cd "$ARMBIAN"
./compile.sh build \
    BOARD=orangepi3 \
    BRANCH=current \
    BUILD_MINIMAL=yes \
    BUILD_DESKTOP=no \
    DEST_LANG=en_US.UTF-8 \
    KERNEL_CONFIGURE=no \
    PREFER_DOCKER=yes \
    RELEASE=resolute \
    SKIP_BOOTSPLASH=yes \
    EXPERT=yes \
    ENABLE_EXTENSIONS=orangepi3-pcie \
    2>&1 | tee "$(pwd)/build-orangepi3.log"

IMG="$(ls -t "$OUTDIR"/*.img 2>/dev/null | head -1 || true)"
log "Done."
[ -n "$IMG" ] && echo "Image: $IMG"
cat <<'EOF'

Post-flash verification on the board:
    dmesg | grep "fallback armed"
        -> expect: missed-MSI fallback armed: period_ms=1 credit_ms=100 irq=NNN
    iperf3 -c <peer> -t 10          # expect >= 700 Mbit/s each direction
EOF
