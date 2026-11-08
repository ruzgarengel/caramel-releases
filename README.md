# Caramel 🍬

A tiny keyboard & mouse macro recorder for macOS, Linux (Wayland/Hyprland ready) and Windows.

This repository hosts Caramel's installers and release downloads.

## Install

**macOS / Linux**
```sh
curl -fsSL https://ruz.one/caramel.sh | bash
```

**Windows** (PowerShell)
```powershell
irm https://ruz.one/caramel.ps1 | iex
```

Run the same command again to update.

The installer downloads the latest release, verifies its SHA-256 checksum and sets everything up:
- **macOS**: installs `Caramel.app` into Applications and asks for the Input Monitoring and Accessibility permissions.
- **Linux**: installs into `~/.local`, adds an app menu entry, and (with one `sudo` prompt) adds you to the `input`
  group and sets up `/dev/uinput`. You only need to log out and back in once after that.
- **Windows**: installs into `%LOCALAPPDATA%\Programs\Caramel` with a Start menu shortcut and a `caramel` command.

## Uninstall

```sh
curl -fsSL https://ruz.one/caramel.sh | bash -s -- --uninstall
```
```powershell
$env:CARAMEL_UNINSTALL=1; irm https://ruz.one/caramel.ps1 | iex
```
(On Windows you can also uninstall Caramel from *Settings → Apps*.)

Your macros are kept.

## Manual downloads

See [Releases](../../releases/latest): `Caramel-macos-universal.dmg`, `caramel-linux-<arch>.tar.gz`,
`caramel-windows-<arch>.zip`, and a `PKGBUILD` for Arch Linux (`makepkg -si`).

## Usage

| Button | Hotkey | |
|---|---|---|
| Rec | F8 | start / stop recording |
| Play | F9 | play / stop the selected macro |
| | F10 | cancel |

Speed, repeat count and the light/dark theme are under **Prefs**.
