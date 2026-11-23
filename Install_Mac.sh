#!/usr/bin/env bash
# SpotX macOS – Quick Installer
# Downloads and runs the SpotX macOS patcher with new-theme and all features enabled.
#
# Usage (paste in Terminal):
#   bash <(curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/Install_Mac.sh)

set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.sh"
TMP_SCRIPT=$(mktemp /tmp/spotx_mac_XXXXXX.sh)
trap 'rm -f "$TMP_SCRIPT"' EXIT

echo "Downloading SpotX macOS patcher …"
curl --silent --fail --location "$SCRIPT_URL" -o "$TMP_SCRIPT"
chmod +x "$TMP_SCRIPT"

exec bash "$TMP_SCRIPT" --new-theme "$@"
