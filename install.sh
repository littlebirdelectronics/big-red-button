#!/usr/bin/env bash
# Big Red Button installer for macOS and Linux (including Raspberry Pi).
#
#   curl -fsSL https://littlebirdelectronics.com.au/install/big-red-button.sh | bash
#   curl -fsSL https://littlebirdelectronics.com.au/install/big-red-button.sh | bash -s -- --uninstall
#
# macOS: installs "Big Red Button.app" (a menu bar app) into /Applications and opens it.
# Linux: installs /usr/local/bin/bigredbutton plus a systemd service; needs sudo.
set -euo pipefail

REPO="littlebirdelectronics/big-red-button"
BASE_URL="${BRB_BASE_URL:-https://github.com/$REPO/releases/latest/download}"
HELP_URL="https://littlebirdelectronics.com.au/help/big-red-button-setup"
APP_NAME="Big Red Button.app"

say() { printf '\033[1;31m●\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "this installer needs '$1' — please install it and try again"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

download() { # url dest
  curl -fsSL --retry 3 -o "$2" "$1" || die "couldn't download $1"
}

# Checks a downloaded file against the release's SHA256SUMS (skipped if the release has none).
verify() { # file asset-name
  if curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$BASE_URL/SHA256SUMS" 2>/dev/null; then
    local want got
    want="$(awk -v f="$2" '$2 == f || $2 == "*"f {print $1}' "$TMP/SHA256SUMS")"
    [ -n "$want" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$1" | awk '{print $1}')"; else got="$(shasum -a 256 "$1" | awk '{print $1}')"; fi
    [ "$want" = "$got" ] || die "checksum mismatch for $2 — the download may be corrupt, please try again"
  fi
}

# ---------------------------------------------------------------- macOS

macos_app_dir() {
  if [ -d "/Applications/$APP_NAME" ] || [ -w /Applications ]; then echo /Applications; else echo "$HOME/Applications"; fi
}

install_macos() {
  need curl; need ditto
  local major dir
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 13 ] || die "Big Red Button needs macOS 13 Ventura or newer (this Mac has $(sw_vers -productVersion))"

  say "Downloading Big Red Button for macOS…"
  download "$BASE_URL/BigRedButton-macOS.zip" "$TMP/app.zip"
  verify "$TMP/app.zip" BigRedButton-macOS.zip
  ditto -x -k "$TMP/app.zip" "$TMP"
  [ -d "$TMP/$APP_NAME" ] || die "the download didn't contain $APP_NAME"

  dir="$(macos_app_dir)"
  mkdir -p "$dir"
  if pgrep -x BigRedButton >/dev/null 2>&1; then
    say "Closing the copy that's already running…"
    pkill -x BigRedButton || true
    sleep 1
  fi
  rm -rf "${dir:?}/$APP_NAME"
  ditto "$TMP/$APP_NAME" "$dir/$APP_NAME"
  xattr -dr com.apple.quarantine "$dir/$APP_NAME" 2>/dev/null || true
  say "Installed $dir/$APP_NAME"
  open "$dir/$APP_NAME"

  cat <<EOF

  Big Red Button is running — look for the red dot in your menu bar.

  1. macOS will ask to let Big Red Button receive keystrokes ("Input Monitoring").
     Click "Open System Settings" and switch Big Red Button on.
  2. Plug the button in with the USB-A to USB-C cable it came with
     (it won't power up on a USB-C to USB-C cable).
  3. Press it! Out of the box it plays a game-show buzzer. Click the red dot
     in the menu bar to make it press a shortcut, type text, run a command,
     open an app or website, or play a different sound.

  Help: $HELP_URL

EOF
}

uninstall_macos() {
  pkill -x BigRedButton 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME" \
    "$HOME/Library/Application Support/BigRedButton" "$HOME/Library/Logs/BigRedButton.log"
  defaults delete au.com.littlebirdelectronics.bigredbutton >/dev/null 2>&1 || true
  # Put the button back to a plain Enter key in case the app couldn't.
  hidutil property --matching '{"VendorID":0x8189,"ProductID":0x19}' --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true
  say "Big Red Button has been removed. You can also remove it from System Settings → Privacy & Security → Input Monitoring."
}

# ---------------------------------------------------------------- Linux

SUDO=""
linux_prepare() {
  need curl
  if [ "$(id -u)" -ne 0 ]; then
    need sudo
    SUDO="sudo"
    say "Some steps need administrator rights, so you may be asked for your password."
  fi
}

install_linux() {
  linux_prepare
  local arch run_as asset
  case "$(uname -m)" in
    aarch64|arm64) arch=arm64 ;;
    armv6l|armv7l|armv8l) arch=armv6 ;;
    x86_64|amd64) arch=amd64 ;;
    *) die "sorry, $(uname -m) isn't supported yet" ;;
  esac
  asset="bigredbutton-linux-$arch"
  # Commands the button runs should run as the person installing it, not root.
  run_as="${SUDO_USER:-$(id -un)}"

  say "Downloading bigredbutton for Linux ($arch)…"
  download "$BASE_URL/$asset" "$TMP/bigredbutton"
  verify "$TMP/bigredbutton" "$asset"
  $SUDO install -m 0755 "$TMP/bigredbutton" /usr/local/bin/bigredbutton

  if [ ! -f /etc/bigredbutton.json ]; then
    printf '{\n  "action": "enter",\n  "run_as": "%s"\n}\n' "$run_as" > "$TMP/bigredbutton.json"
    $SUDO install -m 0644 "$TMP/bigredbutton.json" /etc/bigredbutton.json
  fi

  # The "keys" and "text" actions send keystrokes through uinput; load it now and at every boot.
  echo uinput > "$TMP/bigredbutton.conf"
  $SUDO install -m 0644 "$TMP/bigredbutton.conf" /etc/modules-load.d/bigredbutton.conf 2>/dev/null || true
  $SUDO modprobe uinput 2>/dev/null || true

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    # Same as linux/bigredbutton.service in the repo.
    cat > "$TMP/bigredbutton.service" <<'EOF'
[Unit]
Description=Little Bird Big Red Button
Documentation=https://littlebirdelectronics.com.au/help/big-red-button-setup
After=systemd-udevd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bigredbutton run
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    $SUDO install -m 0644 "$TMP/bigredbutton.service" /etc/systemd/system/bigredbutton.service
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable bigredbutton >/dev/null 2>&1
    $SUDO systemctl restart bigredbutton
    say "Installed and started the bigredbutton service"
  else
    say "systemd wasn't found, so the service wasn't set up. Run it yourself with: sudo bigredbutton run"
  fi

  cat <<EOF

  Big Red Button is installed. Right now the button still presses Enter.
  Tell it what to do instead (commands run as "$run_as"):

    sudo bigredbutton set command "aplay /usr/share/sounds/alsa/Front_Center.wav"
    sudo bigredbutton set command "python3 /home/$run_as/my_script.py"
    sudo bigredbutton set keys "space"        # press a key (held while the button is held)
    sudo bigredbutton set text "Hello!"       # type some text
    sudo bigredbutton set enter               # back to a normal Enter key

    sudo bigredbutton test                    # try the action without pressing the button
    bigredbutton status                       # is the button connected?
    journalctl -u bigredbutton -f             # watch presses live

  Plug the button in with the USB-A to USB-C cable it came with.
  Help: $HELP_URL

EOF
}

uninstall_linux() {
  linux_prepare
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl disable --now bigredbutton >/dev/null 2>&1 || true
    $SUDO rm -f /etc/systemd/system/bigredbutton.service
    $SUDO systemctl daemon-reload || true
  fi
  $SUDO rm -f /usr/local/bin/bigredbutton /etc/bigredbutton.json /etc/modules-load.d/bigredbutton.conf
  say "Big Red Button has been removed."
}

# ---------------------------------------------------------------- main

action="install"
case "${1:-}" in
  --uninstall|uninstall) action="uninstall" ;;
  ""|--install|install) ;;
  -h|--help) sed -n '2,9p' "$0" 2>/dev/null || true; echo "Usage: install.sh [--uninstall]"; exit 0 ;;
  *) die "unknown option: $1 (use --uninstall to remove)" ;;
esac

case "$(uname -s)" in
  Darwin) "${action}_macos" ;;
  Linux) "${action}_linux" ;;
  *) die "this installer works on macOS and Linux. For Windows see $HELP_URL" ;;
esac
