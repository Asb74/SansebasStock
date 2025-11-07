#!/usr/bin/env bash
set -Eeuo pipefail
echo "== Build IPA (SansebasStock) =="

flutter --version
xcodebuild -version

# Limpieza y deps
flutter clean
flutter pub get

# CocoaPods
pushd ios >/dev/null
pod repo update || true
pod install
popd >/dev/null

# Firebase plist
test -f ios/Runner/GoogleService-Info.plist || { echo "❌ Falta ios/Runner/GoogleService-Info.plist"; exit 2; }

# Detectar perfil de firma
INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -z "$PROFILE_PATH" ]]; then
  echo "❌ No hay .mobileprovision en $INSTALL_DIR"; exit 3
fi

TMP_PLIST="$(mktemp /tmp/profile.XXXXXX.plist)"
/usr/bin/security cms -D -i "$PROFILE_PATH" > "$TMP_PLIST"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMP_PLIST")"
TEAM_FROM_PROF="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$TMP_PLIST" 2>/dev/null || true)"
BUNDLE_ID_DETECTED="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$TMP_PLIST" | sed 's/^[^\.]*\.//')"
rm -f "$TMP_PLIST"

echo "Perfil detectado:"
echo "  Name = $PROFILE_NAME"
echo "  Team = ${TEAM_FROM_PROF:-$APPLE_TEAM_ID}"
echo "  BID  = $BUNDLE_ID_DETECTED"

# Export options para App Store
cat > export_options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
</dict>
</plist>
EOF

echo "Export options:"
cat export_options.plist

# Build IPA con export options (manual signing)
flutter build ipa --release --export-options-plist="$(pwd)/export_options.plist" --no-tree-shake-icons

echo "== Artifacts generados =="
find build/ios -type f -name "*.ipa" -print
find build/ios -type d -name "*.dSYM" -print || true

echo "✅ Build IPA DONE"
