#!/usr/bin/env bash
set -euo pipefail

echo "== Build IPA (SansebasStock) =="

flutter clean
flutter pub get
flutter build ios --release --no-codesign

(cd ios && pod install)

echo "== Sanitizar flags de entorno =="
unset CFLAGS CXXFLAGS LDFLAGS OBJCFLAGS OTHER_CFLAGS OTHER_CPLUSPLUSFLAGS OTHER_LDFLAGS GCC_PREPROCESSOR_DEFINITIONS

echo "== Buscar '-G' en ios (diagnóstico) =="
grep -R --line-number --fixed-strings " -G" ios || true
grep -R --line-number --fixed-strings "-G " ios || true
grep -R --line-number --fixed-strings "= -G" ios || true

echo "== Eliminar '-G' de xcconfig y pbxproj =="
find ios -type f \( -name "*.xcconfig" -o -name "project.pbxproj" \) -print0 | while IFS= read -r -d '' f; do
  sed -i '' 's/[[:space:]]-G[[:space:]]/ /g' "$f"
  sed -i '' 's/=-G[[:space:]]/=/g' "$f"
  sed -i '' 's/[[:space:]]-G$//g' "$f"
  sed -i '' 's/^-G[[:space:]]//g' "$f"
done

echo "== Confirmación tras saneo =="
grep -R --line-number --fixed-strings " -G" ios || true
grep -R --line-number --fixed-strings "-G " ios || true
grep -R --line-number --fixed-strings "= -G" ios || true

INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -z "$PROFILE_PATH" ]]; then
  echo "❌ No hay .mobileprovision en $INSTALL_DIR"; exit 3
fi

TMP_PLIST="$(mktemp /tmp/profile.XXXXXX.plist)"
/usr/bin/security cms -D -i "$PROFILE_PATH" > "$TMP_PLIST"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMP_PLIST")"
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$TMP_PLIST")"
TEAM_FROM_PROF="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$TMP_PLIST" 2>/dev/null || true)"
BUNDLE_ID_DETECTED="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$TMP_PLIST" | sed 's/^[^\.]*\.//')"
rm -f "$TMP_PLIST"

echo "Perfil detectado:"
echo "  Name = $PROFILE_NAME"
echo "  UUID = $PROFILE_UUID"
echo "  Team = ${TEAM_FROM_PROF:-$APPLE_TEAM_ID}"
echo "  BID  = $BUNDLE_ID_DETECTED"

cat > export_options.plist <<EOF2
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
EOF2

xcodebuild -workspace ios/Runner.xcworkspace \
           -scheme Runner \
           -configuration Release \
           -archivePath build/Runner.xcarchive archive \
           CODE_SIGN_STYLE=Manual \
           DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
           PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
           PROVISIONING_PROFILE_SPECIFIER="${PROFILE_NAME}" \
           PROVISIONING_PROFILE="${PROFILE_UUID}"

mkdir -p build/ipa
xcodebuild -exportArchive \
           -archivePath build/Runner.xcarchive \
           -exportOptionsPlist export_options.plist \
           -exportPath build/ipa

FINAL_IPA="build/ipa/Runner.ipa"
FOUND_IPA="$(find build/ipa -maxdepth 1 -type f -name "*.ipa" | head -n1 || true)"
if [[ -n "$FOUND_IPA" && "$FOUND_IPA" != "$FINAL_IPA" ]]; then
  mv "$FOUND_IPA" "$FINAL_IPA"
fi

if [[ ! -f "$FINAL_IPA" ]]; then
  echo "❌ No se generó Runner.ipa"; exit 4
fi

echo "✅ IPA generado en $FINAL_IPA"
