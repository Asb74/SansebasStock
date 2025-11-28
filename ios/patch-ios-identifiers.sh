#!/usr/bin/env bash
set -euo pipefail

PLIST_RUNNER="ios/Runner/Info.plist"
PLIST_GOOGLE="ios/Runner/GoogleService-Info.plist"

echo "== Patch iOS identifiers =="

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

# --- Background fetch para notificaciones remotas (clave de Info.plist, NO entitlement) ---
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST_RUNNER" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes array" "$PLIST_RUNNER"
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST_RUNNER" | grep -q "remote-notification" || \
  /usr/libexec/PlistBuddy -c "Add :UIBackgroundModes:0 string remote-notification" "$PLIST_RUNNER"

echo "✅ Patch completo"

