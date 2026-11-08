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
# `uaccess` gives the logged-in user access right away (no re-login); the
# `input` group is a fallback for systems without systemd-logind. The file must
# sort before 73-seat-late.rules for `uaccess` to apply, hence 70-.
UDEV_FILE=/etc/udev/rules.d/70-caramel.rules
UDEV_RULE='KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"'

stop_caramel() {
    pkill -x caramel >/dev/null 2>&1 || return 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x caramel >/dev/null 2>&1 || return 0
        sleep 0.2
    done
    pkill -9 -x caramel >/dev/null 2>&1 || true
}

# Can this user read the keyboards and write /dev/uinput?
input_ok() {
    [ -w /dev/uinput ] || return 1
    local ev found=0
    for ev in $(grep -E '^H: Handlers=.*kbd' /proc/bus/input/devices 2>/dev/null | grep -oE 'event[0-9]+'); do
        found=1
        [ -r "/dev/input/$ev" ] || return 1
    done
    [ "$found" = 1 ]
}

linux() {
    local prefix="${PREFIX:-$HOME/.local}"
    local sudo=sudo
    [ "$(id -u)" = 0 ] && sudo=
    local files=("$prefix/bin/caramel" "$prefix/share/applications/caramel.desktop"
                 "$prefix/share/icons/hicolor/256x256/apps/caramel.png")

    if [ "$UNINSTALL" = 1 ]; then
        say "removing Caramel"
        stop_caramel
        rm -f "${files[@]}"
        ok "removed (your macros are kept in ~/.local/share/caramel)"
        if [ -f "$UDEV_FILE" ] || [ -f /etc/udev/rules.d/99-caramel.rules ]; then
            if ask "Also remove Caramel's input permission rules"; then
                $sudo rm -f "$UDEV_FILE" /etc/udev/rules.d/99-caramel.rules /etc/modules-load.d/caramel.conf
                $sudo udevadm control --reload 2>/dev/null || true
                ok "removed udev rules"
            fi
        fi
        return
    fi

    say "installing Caramel for Linux ($ARCH)"
    local asset="caramel-linux-$ARCH.tar.gz"
    fetch "$asset"
    tar --warning=no-unknown-keyword -xzf "$TMP/$asset" -C "$TMP" 2>/dev/null || tar -xzf "$TMP/$asset" -C "$TMP"
    local src="$TMP/caramel-linux-$ARCH"
    [ -x "$src/caramel" ] || die "unexpected archive layout"

    # Replace any previous installation cleanly.
    if [ -e "$prefix/bin/caramel" ] || pgrep -x caramel >/dev/null 2>&1; then
        stop_caramel
        rm -f "${files[@]}"
        ok "removed the previous installation"
    fi
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

    # Input permissions. Also re-applied when the installed rule is outdated.
    local rule_current=0
    [ -f "$UDEV_FILE" ] && [ "$(cat "$UDEV_FILE")" = "$UDEV_RULE" ] && rule_current=1
    if [ "$rule_current" = 1 ] && input_ok; then
        ok "input permissions already set up"
    else
        echo >&2
        say "Caramel needs access to your input devices (uses sudo, no re-login needed):"
        echo "    - read keyboard/mouse events (to record)" >&2
        echo "    - write /dev/uinput (to play back)" >&2
        if ask "Set this up now"; then
            # Remove rules from older Caramel versions / manual setup.
            $sudo rm -f /etc/udev/rules.d/99-caramel.rules
            if [ -f /etc/modules-load.d/uinput.conf ] && [ "$(tr -d '[:space:]' </etc/modules-load.d/uinput.conf)" = uinput ]; then
                $sudo rm -f /etc/modules-load.d/uinput.conf
            fi
            printf '%s\n' "$UDEV_RULE" | $sudo tee "$UDEV_FILE" >/dev/null
            echo uinput | $sudo tee /etc/modules-load.d/caramel.conf >/dev/null
            $sudo modprobe uinput || true
            $sudo udevadm control --reload || true
            $sudo udevadm trigger --action=change --subsystem-match=input --subsystem-match=misc || true
            $sudo udevadm settle --timeout=5 2>/dev/null || true
            # Grant this session access immediately as well (udev covers future boots).
            if command -v setfacl >/dev/null 2>&1; then
                $sudo setfacl -m "u:$USER:rw" /dev/uinput 2>/dev/null || true
                for d in /dev/input/event*; do $sudo setfacl -m "u:$USER:r" "$d" 2>/dev/null || true; done
            fi
            id -nG "$USER" | tr ' ' '\n' | grep -qx input || $sudo usermod -aG input "$USER" || true
            if input_ok; then
                ok "input permissions configured"
            else
                warn "permissions are set, but this session can't use them yet: log out and back in once"
            fi
        else
            warn "skipped; run 'caramel setup' later for the commands"
        fi
    fi

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        ok "Hyprland detected: pixel-exact mouse recording via Hyprland IPC"
    fi
    echo >&2
    if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
        say "done. Starting Caramel..."
        if command -v setsid >/dev/null 2>&1; then
            setsid -f "$prefix/bin/caramel" >/dev/null 2>&1 </dev/null || true
        else
            nohup "$prefix/bin/caramel" >/dev/null 2>&1 </dev/null &
        fi
    else
        say "done. Start it from your app menu or run: caramel"
    fi
}

case "$(uname -s)" in
    Darwin) macos ;;
    Linux) linux ;;
    *) die "unsupported OS: $(uname -s) (on Windows use: irm https://ruz.one/caramel.ps1 | iex)" ;;
esac
