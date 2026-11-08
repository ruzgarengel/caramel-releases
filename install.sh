#!/usr/bin/env bash
# Caramel installer for macOS and Linux.
#
#   curl -fsSL https://ruz.one/caramel.sh | bash                    # install / update
#   curl -fsSL https://ruz.one/caramel.sh | bash -s -- --uninstall  # remove
#
# Environment:
#   CARAMEL_VERSION=0.1.0   install a specific version instead of the latest
#   CARAMEL_YES=1           answer "yes" to every question (non-interactive)
#   PREFIX=/usr/local       Linux install prefix (default: ~/.local)
set -euo pipefail

REPO="ruzgarengel/caramel-releases"
if [ -n "${CARAMEL_VERSION:-}" ]; then
    BASE="https://github.com/$REPO/releases/download/v${CARAMEL_VERSION#v}"
else
    BASE="https://github.com/$REPO/releases/latest/download"
fi
BASE="${CARAMEL_BASE_URL:-$BASE}"

# ───────────────────────────── helpers ─────────────────────────────
if [ -t 2 ]; then B=$'\033[1m'; Y=$'\033[33m'; G=$'\033[32m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B= Y= G= R= D= N=; fi
say()  { printf '%s\n' "${B}${Y}caramel${N} $*" >&2; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*" >&2; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# Ask a yes/no question on the terminal (stdin is this script when piped).
ask() {
    [ "${CARAMEL_YES:-}" = 1 ] && return 0
    [ -r /dev/tty ] || return 1
    local ans
    printf '  %s? %s[Y/n]%s ' "$*" "$D" "$N" >&2
    read -r ans </dev/tty || return 1
    case "$ans" in [nN]*) return 1 ;; *) return 0 ;; esac
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"; }

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Download a release asset into $TMP and verify it against SHA256SUMS.
fetch() {
    local file=$1
    [ -f "$TMP/SHA256SUMS" ] || curl -fsSL "$BASE/SHA256SUMS" -o "$TMP/SHA256SUMS" \
        || die "couldn't reach $BASE (no release published yet?)"
    curl -fL --progress-bar "$BASE/$file" -o "$TMP/$file" || die "download failed: $file"
    local want got
    want=$(awk -v f="$file" '$2 == f || $2 == "*"f {print $1}' "$TMP/SHA256SUMS")
    got=$(sha256 "$TMP/$file")
    [ -n "$want" ] || die "$file is missing from SHA256SUMS"
    [ "$want" = "$got" ] || die "checksum mismatch for $file"
    ok "downloaded and verified $file"
}

UNINSTALL=0
for a in "$@"; do
    case "$a" in
        --uninstall|-u) UNINSTALL=1 ;;
        -y|--yes) CARAMEL_YES=1 ;;
        *) die "unknown option: $a" ;;
    esac
done

need curl
need tar

case "$(uname -m)" in
    x86_64|amd64) ARCH=x86_64 ;;
    arm64|aarch64) ARCH=aarch64 ;;
    *) die "unsupported CPU architecture: $(uname -m)" ;;
esac

# ───────────────────────────── macOS ─────────────────────────────
macos() {
    local apps=/Applications
    [ -w "$apps" ] || apps="$HOME/Applications"
    local app="$apps/Caramel.app" bin_dir=/usr/local/bin
    [ -w "$bin_dir" ] || bin_dir="$HOME/.local/bin"

    if [ "$UNINSTALL" = 1 ]; then
        say "removing Caramel"
        osascript -e 'quit app "Caramel"' >/dev/null 2>&1 || true
        rm -rf "/Applications/Caramel.app" "$HOME/Applications/Caramel.app"
        rm -f "/usr/local/bin/caramel" "$HOME/.local/bin/caramel"
        tccutil reset ListenEvent app.caramel.Caramel >/dev/null 2>&1 || true
        tccutil reset Accessibility app.caramel.Caramel >/dev/null 2>&1 || true
        ok "removed (your macros are kept in ~/Library/Application Support/caramel)"
        return
    fi

    say "installing Caramel for macOS"
    fetch caramel-macos-universal.tar.gz

    local updating=0
    if [ -d "$app" ]; then
        updating=1
        osascript -e 'quit app "Caramel"' >/dev/null 2>&1 || true
        pkill -x caramel >/dev/null 2>&1 || true
        sleep 0.5
    fi
    mkdir -p "$apps"
    rm -rf "$app"
    tar -xzf "$TMP/caramel-macos-universal.tar.gz" -C "$apps"
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
    ok "installed $app"

    mkdir -p "$bin_dir"
    ln -sf "$app/Contents/MacOS/caramel" "$bin_dir/caramel"
    ok "command line: $bin_dir/caramel"
    case ":$PATH:" in *":$bin_dir:"*) ;; *) warn "$bin_dir is not on your PATH" ;; esac

    if [ "$updating" = 1 ]; then
        # The app is ad-hoc signed, so macOS treats each version as a new app:
        # clear the old permission entries so the prompts show up again.
        tccutil reset ListenEvent app.caramel.Caramel >/dev/null 2>&1 || true
        tccutil reset Accessibility app.caramel.Caramel >/dev/null 2>&1 || true
    fi

    echo >&2
    say "almost done: macOS will ask for two permissions"
    echo "    1. Input Monitoring  (recording + F8/F9/F10 hotkeys)" >&2
    echo "    2. Accessibility     (playback)" >&2
    echo "    Enable Caramel in both dialogs / System Settings, then reopen Caramel." >&2
    open "$app"
}

# ───────────────────────────── Linux ─────────────────────────────
linux() {
    local prefix="${PREFIX:-$HOME/.local}"
    local sudo=sudo
    [ "$(id -u)" = 0 ] && sudo=

    if [ "$UNINSTALL" = 1 ]; then
        say "removing Caramel"
        pkill -x caramel >/dev/null 2>&1 || true
        rm -f "$prefix/bin/caramel" "$prefix/share/applications/caramel.desktop" \
              "$prefix/share/icons/hicolor/256x256/apps/caramel.png"
        ok "removed (your macros are kept in ~/.local/share/caramel)"
        if [ -f /etc/udev/rules.d/99-caramel.rules ] && ask "Also remove the uinput udev rule and module config"; then
            $sudo rm -f /etc/udev/rules.d/99-caramel.rules /etc/modules-load.d/caramel.conf
            $sudo udevadm control --reload 2>/dev/null || true
            ok "removed udev rule"
        fi
        return
    fi

    say "installing Caramel for Linux ($ARCH)"
    local asset="caramel-linux-$ARCH.tar.gz"
    fetch "$asset"
    tar -xzf "$TMP/$asset" -C "$TMP"
    local src="$TMP/caramel-linux-$ARCH"
    [ -x "$src/caramel" ] || die "unexpected archive layout"

    pkill -x caramel >/dev/null 2>&1 || true
    install -Dm755 "$src/caramel" "$prefix/bin/caramel"
    sed "s|^Exec=caramel|Exec=$prefix/bin/caramel|" "$src/caramel.desktop" > "$TMP/caramel.desktop"
    install -Dm644 "$TMP/caramel.desktop" "$prefix/share/applications/caramel.desktop"
    install -Dm644 "$src/caramel.png" "$prefix/share/icons/hicolor/256x256/apps/caramel.png"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
    ok "installed $prefix/bin/caramel (app menu: Caramel)"
    case ":$PATH:" in *":$prefix/bin:"*) ;; *) warn "$prefix/bin is not on your PATH" ;; esac

    # Runtime libraries the UI loads (Wayland/X11 + EGL).
    local missing=()
    for lib in libwayland-client.so.0 libxkbcommon.so.0 libEGL.so.1; do
        if ! { ldconfig -p 2>/dev/null || true; } | grep -q "$lib"; then missing+=("$lib"); fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        local cmd=""
        if command -v pacman >/dev/null; then cmd="pacman -S --needed wayland libxkbcommon libglvnd"
        elif command -v apt-get >/dev/null; then cmd="apt-get install -y libwayland-client0 libxkbcommon0 libegl1"
        elif command -v dnf >/dev/null; then cmd="dnf install -y libwayland-client libxkbcommon libglvnd-egl"
        elif command -v zypper >/dev/null; then cmd="zypper install -y libwayland-client0 libxkbcommon0 libEGL1"
        fi
        warn "missing libraries: ${missing[*]}"
        if [ -n "$cmd" ] && ask "Install them now ($cmd)"; then
            $sudo $cmd
        else
            warn "install them with your package manager before starting Caramel"
        fi
    fi

    # Permissions: read /dev/input (input group) and write /dev/uinput.
    local in_group=0
    id -nG "$USER" | tr ' ' '\n' | grep -qx input && in_group=1
    if [ "$in_group" = 1 ] && [ -w /dev/uinput ]; then
        ok "input permissions already set up"
    else
        echo >&2
        say "Caramel needs access to input devices (one-time, uses sudo):"
        echo "    - add $USER to the 'input' group (to record)" >&2
        echo "    - allow the 'input' group to use /dev/uinput (to play back)" >&2
        if ask "Set this up now"; then
            [ "$in_group" = 1 ] || $sudo usermod -aG input "$USER"
            echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
                | $sudo tee /etc/udev/rules.d/99-caramel.rules >/dev/null
            echo uinput | $sudo tee /etc/modules-load.d/caramel.conf >/dev/null
            $sudo modprobe uinput || true
            $sudo udevadm control --reload || true
            $sudo udevadm trigger || true
            ok "permissions configured"
            [ "$in_group" = 1 ] || warn "log out and back in once so the group change takes effect"
        else
            warn "skipped; run 'caramel setup' later for the commands"
        fi
    fi

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        ok "Hyprland detected: pixel-exact mouse recording via Hyprland IPC"
    fi
    echo >&2
    say "done. Start it from your app menu or run: caramel"
}

case "$(uname -s)" in
    Darwin) macos ;;
    Linux) linux ;;
    *) die "unsupported OS: $(uname -s) (on Windows use: irm https://ruz.one/caramel.ps1 | iex)" ;;
esac
