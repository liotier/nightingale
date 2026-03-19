#!/usr/bin/env bash
# deploy-debian.sh — Build and install Nightingale on Debian/Ubuntu.
#
# Usage:
#   sudo ./scripts/deploy-debian.sh            # full install
#   sudo ./scripts/deploy-debian.sh --no-analyzer  # skip Python analyzer
#   sudo ./scripts/deploy-debian.sh --uninstall    # remove installation
#
# Installs:
#   /opt/nightingale/          — binary, assets, analyzer venv
#   /usr/local/bin/nightingale — symlink
#   /usr/share/applications/nightingale.desktop
#   /usr/share/icons/hicolor/256x256/apps/nightingale.png
set -euo pipefail

REPO_URL="https://github.com/liotier/nightingale.git"
BRANCH="claude/add-key-detection-KL7OB"
INSTALL_DIR="/opt/nightingale"
BUILD_DIR="/tmp/nightingale-build"
SKIP_ANALYZER=false

# ── Helpers ──────────────────────────────────────────────────────────
info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }
die()   { err "$@"; exit 1; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root (try: sudo $0)"
    fi
}

# ── Uninstall ────────────────────────────────────────────────────────
uninstall() {
    require_root
    info "Removing Nightingale installation..."
    rm -f  /usr/local/bin/nightingale
    rm -f  /usr/share/applications/nightingale.desktop
    rm -f  /usr/share/icons/hicolor/256x256/apps/nightingale.png
    rm -rf "$INSTALL_DIR"
    info "Uninstalled."
    exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-analyzer) SKIP_ANALYZER=true ;;
        --uninstall)   uninstall ;;
        -h|--help)
            sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

require_root

# ── Detect architecture ─────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  RUST_TARGET="x86_64-unknown-linux-gnu" ;;
    aarch64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
    *)       die "Unsupported architecture: $ARCH" ;;
esac

# ── System dependencies ─────────────────────────────────────────────
info "Installing system dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    git \
    curl \
    libudev-dev \
    libasound2-dev \
    libwayland-dev \
    libxkbcommon-dev \
    libvulkan-dev

# Python for the analyzer (GPU-accelerated ML inference).
if [ "$SKIP_ANALYZER" = false ]; then
    apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-pip \
        ffmpeg
fi

# ── Rust toolchain ───────────────────────────────────────────────────
export RUSTUP_INIT_SKIP_PATH_CHECK=yes
if ! command -v rustup &>/dev/null; then
    info "Installing Rust toolchain..."
    # Run rustup as the invoking user if possible, else as root.
    SUDO_USER="${SUDO_USER:-root}"
    if [ "$SUDO_USER" != "root" ]; then
        su - "$SUDO_USER" -c "export RUSTUP_INIT_SKIP_PATH_CHECK=yes; curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    fi
fi
# Make cargo available in this shell.
for p in "/home/${SUDO_USER:-root}/.cargo/bin" "$HOME/.cargo/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
done
command -v cargo &>/dev/null || die "cargo not found — check Rust installation"

RUST_VER="$(rustc --version | awk '{print $2}')"
info "Using Rust $RUST_VER (target: $RUST_TARGET)"

# ── Clone / update source ───────────────────────────────────────────
if [ -d "$BUILD_DIR/.git" ]; then
    info "Updating existing source in $BUILD_DIR..."
    git -C "$BUILD_DIR" fetch origin "$BRANCH"
    git -C "$BUILD_DIR" checkout "$BRANCH"
    git -C "$BUILD_DIR" reset --hard "origin/$BRANCH"
else
    info "Cloning repository..."
    rm -rf "$BUILD_DIR"
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$BUILD_DIR"
fi

cd "$BUILD_DIR"

# ── Build ────────────────────────────────────────────────────────────
info "Building release binary (this may take a while)..."
if [ -f .env ]; then
    set -a; source .env; set +a
fi
cargo build --release --target "$RUST_TARGET"

BINARY="target/$RUST_TARGET/release/nightingale"
[ -f "$BINARY" ] || die "Build failed — binary not found at $BINARY"

# ── Install ──────────────────────────────────────────────────────────
info "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Binary.
install -m 755 "$BINARY" "$INSTALL_DIR/nightingale"

# Assets (fonts, images, shaders, etc. — needed at runtime).
if [ -d assets ]; then
    cp -a assets "$INSTALL_DIR/"
fi

# Analyzer (Python ML pipeline).
if [ "$SKIP_ANALYZER" = false ] && [ -d analyzer ]; then
    info "Setting up Python analyzer..."
    cp -a analyzer "$INSTALL_DIR/"
    bash "$INSTALL_DIR/analyzer/setup.sh"
fi

# Symlink into PATH.
ln -sf "$INSTALL_DIR/nightingale" /usr/local/bin/nightingale

# Desktop integration.
if [ -f packaging/linux/nightingale.desktop ]; then
    install -Dm 644 packaging/linux/nightingale.desktop \
        /usr/share/applications/nightingale.desktop
    # Ensure Exec= points to our install location.
    sed -i "s|^Exec=.*|Exec=$INSTALL_DIR/nightingale|" \
        /usr/share/applications/nightingale.desktop
fi

if [ -f assets/images/logo_square.png ]; then
    install -Dm 644 assets/images/logo_square.png \
        /usr/share/icons/hicolor/256x256/apps/nightingale.png
fi

# ── Summary ──────────────────────────────────────────────────────────
BIN_SIZE="$(du -h "$INSTALL_DIR/nightingale" | cut -f1)"

info "Installation complete!"
echo ""
echo "  Binary:    $INSTALL_DIR/nightingale ($BIN_SIZE)"
echo "  Symlink:   /usr/local/bin/nightingale"
echo "  Desktop:   /usr/share/applications/nightingale.desktop"
echo "  Assets:    $INSTALL_DIR/assets/"
if [ "$SKIP_ANALYZER" = false ] && [ -d "$INSTALL_DIR/analyzer" ]; then
    echo "  Analyzer:  $INSTALL_DIR/analyzer/"
fi
echo ""
echo "  Run:       nightingale"
echo "  Uninstall: sudo $0 --uninstall"
