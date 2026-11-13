#!/bin/zsh
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/AlparslanSemiz/Kumanda/main/install.sh | zsh
# Builds Kumanda from source on your Mac (so Gatekeeper has nothing to quarantine),
# installs it to ~/Applications and opens it. Login start is a menu toggle.
set -euo pipefail

REPO="https://github.com/AlparslanSemiz/Kumanda.git"
SRC="$HOME/.local/src/Kumanda"

if [[ "$(uname)" != "Darwin" ]]; then echo "Kumanda runs on macOS only."; exit 1; fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Kumanda needs Apple's Command Line Tools to build. Starting the installer…"
  xcode-select --install || true
  echo "Run this script again when the Command Line Tools are installed."; exit 1
fi

echo "→ Getting the source"
if [[ -d "$SRC/.git" ]]; then git -C "$SRC" pull --ff-only --quiet
else mkdir -p "${SRC:h}"; git clone --quiet --depth 1 "$REPO" "$SRC"; fi

echo "→ Building"
"$SRC/build.sh"

echo
echo "Done. One permission is left: System Settings → Privacy & Security → Accessibility → Kumanda."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
