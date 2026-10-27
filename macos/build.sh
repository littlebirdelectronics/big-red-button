#!/usr/bin/env bash
# Builds "Big Red Button.app" (universal arm64 + x86_64), signs it and zips it into build/.
#   VERSION=1.0.0 ./build.sh
# Signs with the Little Bird Developer ID by default; SIGN_ID=- for an ad-hoc build.
# Set NOTARY_PROFILE to a `notarytool store-credentials` profile to notarise and staple too.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
SIGN_ID="${SIGN_ID:-Developer ID Application: Little Bird IT (RWFD69KX56)}"
BUILD=build
APP="$BUILD/Big Red Button.app"
ZIP="$BUILD/BigRedButton-macOS.zip"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"

[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift Resources/AppIcon.icns
[ -f Resources/Sounds/Buzzer.wav ] || python3 scripts/make-sounds.py

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -o "$BUILD/BigRedButton-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/BigRedButton" "$BUILD/BigRedButton-arm64" "$BUILD/BigRedButton-x86_64"
rm "$BUILD"/BigRedButton-{arm64,x86_64}

sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/Sounds/"

# The hardened runtime refuses Apple Events (osascript in a "command" action) without this entitlement.
ENTITLEMENTS="$BUILD/BigRedButton.entitlements"
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
EOF

if [ "$SIGN_ID" = "-" ]; then
  codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

shasum -a 256 "$ZIP"
echo "Built $APP ($VERSION) and $ZIP"
