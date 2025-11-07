#!/usr/bin/env bash
set -Eeuo pipefail

echo "== Build IPA (SansebasStock) =="

# Mostrar versiones (útil en logs)
flutter --version
xcodebuild -version

# Limpieza y dependencias
flutter clean
flutter pub get

# CocoaPods (por si hay cambios en plugins)
pushd ios >/dev/null
pod repo update || true
pod install
popd >/dev/null

# Verifica que el plist de Firebase se haya recreado por el paso anterior
test -f ios/Runner/GoogleService-Info.plist || {
  echo "❌ Falta ios/Runner/GoogleService-Info.plist (revisa GOOGLE_SERVICE_INFO_PLIST_B64)."
  exit 2
}

# Compila IPA (firma y perfiles ya preparados en pasos previos)
# --no-tree-shake-icons se mantiene para evitar problemas con icon fonts
flutter build ipa --release --no-tree-shake-icons

# Mostrar IPA generado y dSYMs
echo "== Artifacts generados =="
find build/ios -type f -name "*.ipa" -print
find build/ios -type d -name "*.dSYM" -print || true

echo "✅ Build IPA DONE"
