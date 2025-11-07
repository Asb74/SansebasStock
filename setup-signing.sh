# Reescribe build-ipa.sh para usar export-options "app-store" con tu perfil
cat > build-ipa.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "== Build IPA (SansebasStock) =="

# 0) Diagnóstico rápido
flutter --version
xcodebuild -version

# 1) Limpieza y dependencias
flutter clean
flutter pub get

# 2) CocoaPods
pushd ios >/dev/null
pod repo update || true
pod install
popd >/dev/null

# 3) Asegurar que el plist de Firebase existe
test -f ios/Runner/GoogleService-Info.plist || {
  echo "❌ Falta ios/Runner/GoogleService-Info.plist (revisa GOOGLE_SERVICE_INFO_PLIST_B64)."
  exit 2
}

# 4) Detectar perfil instalado y preparar export_options.plist (app-store)
INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -z "$PROFILE_PATH" ]]; then
  echo "❌ No hay .mobileprovision instalado en $INSTALL_DIR"; exit 3
fi

TMP_PLIST="$(mktemp /tmp/profile.XXXXXX.plist)"
/usr/bin/security cms -D -i "$PROFILE_PATH" > "$TMP_PLIST"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMP_PLIST")"
TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$TMP_PLIST" 2>/dev/null || true)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$TMP_PLIST" | sed 's/^[^\.]*\.//')"
rm -f "$TMP_PLIST"

echo "Perfil detectado:"
echo "  Name = $PROFILE_NAME"
echo "  Team = ${TEAM_ID:-$APPLE_TEAM_ID}"
echo "  BID  = $BUNDLE_ID"

# 5) Crear export_options.plist para App Store
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

# 6) Build IPA usando el export_options.plist (firma manual)
flutter build ipa --release --export-options-plist="$(pwd)/export_options.plist" --no-tree-shake-icons

# 7) Mostrar artefactos
echo "== Artifacts generados =="
find build/ios -type f -name "*.ipa" -print
find build/ios -type d -name "*.dSYM" -print || true

echo "✅ Build IPA DONE"
SH

git add build-ipa.sh
git commit -m "ci(ios): build ipa with explicit app-store export options (manual signing)"
git push
