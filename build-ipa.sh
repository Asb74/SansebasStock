#!/usr/bin/env bash
set -euo pipefail

echo "== Build IPA (SansebasStock) =="

flutter clean && flutter pub get

echo "== Refrescar Pods =="
cd ios
rm -rf Pods Podfile.lock
pod repo update
pod install
cd ..

# === Saneo de firma en Pods ===
PODSPROJ="ios/Pods/Pods.xcodeproj/project.pbxproj"

# Elimina cualquier rastro de perfil/equipo/identidad en Pods
/usr/bin/sed -i '' '/PROVISIONING_PROFILE_SPECIFIER = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/PROVISIONING_PROFILE = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/DEVELOPMENT_TEAM = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/CODE_SIGN_IDENTITY = /d' "$PODSPROJ" || true

# Asegura estilo automático y sin firma en todos los bloques de buildSettings
/usr/bin/sed -i '' 's/CODE_SIGN_STYLE = Manual/CODE_SIGN_STYLE = Automatic/g' "$PODSPROJ" || true
/usr/bin/sed -i '' 's/CODE_SIGNING_ALLOWED = YES/CODE_SIGNING_ALLOWED = NO/g' "$PODSPROJ" || true
/usr/bin/sed -i '' 's/CODE_SIGNING_REQUIRED = YES/CODE_SIGNING_REQUIRED = NO/g' "$PODSPROJ" || true

# (opcional) Si existiera alguna clave residual con “SansebasStock IOs ios_app_store”, bórrala por si quedó en comentarios
/usr/bin/sed -i '' '/SansebasStock IOs ios_app_store/d' "$PODSPROJ" || true

# (opcional) saneo anti “-G” si teníamos ese problema
find ios -type f \( -name "*.xcconfig" -o -name "project.pbxproj" \) -print0 | while IFS= read -r -d '' f; do
  sed -i '' 's/[[:space:]]-G[[:space:]]/ /g; s/=-G[[:space:]]/=/g; s/[[:space:]]-G$//g; s/^-G[[:space:]]//g' "$f"
done

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

echo "== Override de firma SOLO para Runner con xcconfig =="
OVR="ios/Runner/CodesignOverride.xcconfig"
cat > "$OVR" <<EOF
// Forzar firma de distribución en Runner
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Distribution
DEVELOPMENT_TEAM = ${APPLE_TEAM_ID}
PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}
PROVISIONING_PROFILE_SPECIFIER = ${PROFILE_NAME}
PROVISIONING_PROFILE = ${PROFILE_UUID}
CODE_SIGNING_ALLOWED = YES
CODE_SIGNING_REQUIRED = YES
EOF

REL_XC="ios/Flutter/Release.xcconfig"
if ! grep -q 'CodesignOverride.xcconfig' "$REL_XC"; then
  echo '#include "Runner/CodesignOverride.xcconfig"' >> "$REL_XC"
fi

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

# Defensivo: evitar restos de Development en Runner
PBX="ios/Runner.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY = iPhone Developer/CODE_SIGN_IDENTITY = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY = iOS Development/CODE_SIGN_IDENTITY = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY\\[sdk=iphoneos\\*\\] = iPhone Developer/CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY\\[sdk=iphoneos\\*\\] = iOS Development/CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g" "$PBX" || true

xcodebuild -workspace ios/Runner.xcworkspace \
           -scheme Runner \
           -configuration Release \
           -destination "generic/platform=iOS" \
           -archivePath build/Runner.xcarchive archive \
           OTHER_CFLAGS= OTHER_CPLUSPLUSFLAGS= OTHER_LDFLAGS= GCC_PREPROCESSOR_DEFINITIONS=

rm -rf build/ipa
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
