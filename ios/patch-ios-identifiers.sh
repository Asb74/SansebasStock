#!/usr/bin/env bash
set -euo pipefail

PLIST_RUNNER="ios/Runner/Info.plist"
PLIST_GOOGLE="ios/Runner/GoogleService-Info.plist"

echo "== Patch iOS identifiers (SansebasStock) =="

# --- Asegurar Bundle ID y Team ID ---
: "${BUNDLE_ID:?Falta BUNDLE_ID}"
: "${APPLE_TEAM_ID:?Falta APPLE_TEAM_ID}"

echo "Bundle ID: $BUNDLE_ID"
echo "Team ID:   $APPLE_TEAM_ID"

# --- (Opcional) URL scheme desde REVERSED_CLIENT_ID si existe ---
if [[ -s "$PLIST_GOOGLE" ]] && /usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$PLIST_GOOGLE" >/dev/null 2>&1; then
  REV=$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$PLIST_GOOGLE")
  echo "Found REVERSED_CLIENT_ID: $REV"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST_RUNNER" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST_RUNNER" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST_RUNNER" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST_RUNNER" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $REV" "$PLIST_RUNNER" >/dev/null 2>&1 || true
  echo "✅ URL scheme aplicado"
else
  echo "ℹ️  REVERSED_CLIENT_ID no existe en GoogleService-Info.plist; se omite el patch de URL scheme"
fi

# --- Actualizar CFBundleIdentifier en Info.plist ---
if [ -f "$PLIST_RUNNER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST_RUNNER" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST_RUNNER"
  echo "✅ CFBundleIdentifier actualizado"
else
  echo "❌ No se encontró $PLIST_RUNNER"
fi

# --- Actualizar DEVELOPMENT_TEAM y PRODUCT_BUNDLE_IDENTIFIER en project.pbxproj ---
PBX="ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$PBX" ]; then
  sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/" "$PBX"
  sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]\{10\}/DEVELOPMENT_TEAM = $APPLE_TEAM_ID/g" "$PBX"
  echo "✅ project.pbxproj actualizado"
else
  echo "❌ No se encontró $PBX"
fi

# --- Background fetch para notificaciones remotas ---
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST_RUNNER" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST_RUNNER"
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST_RUNNER" | grep -q "remote-notification" || \
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string remote-notification" "$PLIST_RUNNER"

echo "✅ Patch completo (SansebasStock)"
