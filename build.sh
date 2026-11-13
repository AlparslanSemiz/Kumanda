#!/bin/zsh
# Kumanda'yı derler, ~/Applications/Kumanda.app olarak kurar ve açar.
#   ./build.sh               -> derle + kur + aç
#   ./build.sh --no-install  -> sadece build/Kumanda.app üret
set -euo pipefail
cd "${0:A:h}"

BUNDLE_ID="${KUMANDA_BUNDLE_ID:-local.$(whoami).kumanda}"
BUILD=build
APP="$BUILD/Kumanda.app"

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/Kumanda.iconset"

echo "→ simge"
swift scripts/make_icon.swift "$BUILD/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$BUILD/Kumanda.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon.png" --out "$BUILD/Kumanda.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/Kumanda.iconset" -o "$APP/Contents/Resources/Kumanda.icns"

echo "→ derleme"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Kumanda" -framework GameController

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Kumanda</string>
<key>CFBundleDisplayName</key><string>Kumanda</string>
<key>CFBundleExecutable</key><string>Kumanda</string>
<key>CFBundleIconFile</key><string>Kumanda</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>Kontrolcüyle Mac'i kullan.</string>
</dict></plist>
PLIST

# A stable local certificate keeps the Accessibility permission across rebuilds.
SIGN_ID="-"
if security find-identity -p codesigning 2>/dev/null | /usr/bin/grep -q "Veda Local Signing"; then
  SIGN_ID="Veda Local Signing"
else
  echo "  (not: yerel imza sertifikası yok, ad-hoc imza kullanılıyor)"
fi
codesign --force -s "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"

[[ "${1:-}" == "--no-install" ]] && { echo "✓ $APP"; exit 0; }

echo "→ kurulum"
DEST="$HOME/Applications/Kumanda.app"
pkill -x Kumanda 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"; cp -R "$APP" "$DEST"
open "$DEST"
echo "✓ Kumanda kuruldu ve açıldı."
echo "  İlk açılışta: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik → Kumanda'yı aç."
