#!/bin/bash
set -Eeuo pipefail

LOG_DIR="build/logs"
XC_LOG_PATH="${LOG_DIR}/xcodebuild-archive.log"
XC_RESULT_BUNDLE="build/XCResultBundle"
PENDING_XC_LOG=""

ensure_log_dir() {
  mkdir -p "$LOG_DIR"
}

collect_diagnostics() {
  echo "=== Recolectando fragmentos de diagnóstico ==="
  ensure_log_dir
  if [[ -f "ios/Pods/leveldb-library/port/port.h" ]]; then
    sed -n '1,160p' ios/Pods/leveldb-library/port/port.h > "${LOG_DIR}/port.h.head.txt" || true
    echo "Fragmento de port.h guardado en ${LOG_DIR}/port.h.head.txt"
  else
    echo "No existe ios/Pods/leveldb-library/port/port.h" > "${LOG_DIR}/port.h.head.txt"
    echo "Archivo ios/Pods/leveldb-library/port/port.h no encontrado; se registró aviso."
  fi

  if [[ -f "ios/Flutter/Release.xcconfig" ]]; then
    sed -n '1,60p' ios/Flutter/Release.xcconfig > "${LOG_DIR}/release_xcconfig.head.txt" || true
    echo "Fragmento de Release.xcconfig guardado en ${LOG_DIR}/release_xcconfig.head.txt"
  else
    echo "No existe ios/Flutter/Release.xcconfig" > "${LOG_DIR}/release_xcconfig.head.txt"
    echo "Archivo ios/Flutter/Release.xcconfig no encontrado; se registró aviso."
  fi
}

package_logs() {
  echo "=== Empaquetando logs y diagnósticos ==="
  ensure_log_dir

  if [[ -n "$PENDING_XC_LOG" && -f "$PENDING_XC_LOG" && "$PENDING_XC_LOG" != "$XC_LOG_PATH" ]]; then
    mv "$PENDING_XC_LOG" "$XC_LOG_PATH"
    echo "Log parcial de xcodebuild movido a ${XC_LOG_PATH}"
  fi

  if [[ ! -f "$XC_LOG_PATH" ]]; then
    echo "Log de xcodebuild no disponible" > "$XC_LOG_PATH"
  fi

  collect_diagnostics

  tar -czf "${LOG_DIR}/xcodebuild-archive.tar.gz" -C "$LOG_DIR" xcodebuild-archive.log *.txt 2>/dev/null || true
  echo "Archivo comprimido disponible en ${LOG_DIR}/xcodebuild-archive.tar.gz"
}

print_logs_tree() {
  ensure_log_dir
  echo "=== Logs disponibles ==="
  pwd
  ls -lah "$LOG_DIR" || true
  echo "=== Árbol completo de ${LOG_DIR} ==="
  ls -R "$LOG_DIR" || true
}

on_error() {
  local exit_code=$?
  local line_no=$1
  echo "❌ Error detectado en build-ipa.sh (línea ${line_no}, código ${exit_code})"
  ensure_log_dir
  package_logs
  print_logs_tree
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

echo "=== Posicionando script en la raíz del repositorio ==="
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

ensure_log_dir
mkdir -p build

echo "=== Build IPA (SansebasStock) ==="

echo "=== Ejecutando flutter clean ==="
flutter clean
echo "=== flutter clean completado ==="

echo "=== Ejecutando flutter pub get ==="
flutter pub get
echo "=== flutter pub get completado ==="

echo "=== Refrescar Pods inicial ==="
pushd ios >/dev/null
rm -rf Pods Podfile.lock
pod repo update
pod install
echo "=== Pods iniciales listos ==="
popd >/dev/null

echo "=== Preparando archivos de firma en Pods ==="
PODSPROJ="ios/Pods/Pods.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' '/PROVISIONING_PROFILE_SPECIFIER = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/PROVISIONING_PROFILE = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/DEVELOPMENT_TEAM = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' '/CODE_SIGN_IDENTITY = /d' "$PODSPROJ" || true
/usr/bin/sed -i '' 's/CODE_SIGN_STYLE = Manual/CODE_SIGN_STYLE = Automatic/g' "$PODSPROJ" || true
/usr/bin/sed -i '' 's/CODE_SIGNING_ALLOWED = YES/CODE_SIGNING_ALLOWED = NO/g' "$PODSPROJ" || true
/usr/bin/sed -i '' 's/CODE_SIGNING_REQUIRED = YES/CODE_SIGNING_REQUIRED = NO/g' "$PODSPROJ" || true
/usr/bin/sed -i '' '/SansebasStock IOs ios_app_store/d' "$PODSPROJ" || true

echo "=== Saneo adicional anti -G en proyectos y xcconfig ==="
find ios -type f \( -name "*.xcconfig" -o -name "project.pbxproj" \) -print0 | while IFS= read -r -d '' f; do
  sed -i '' 's/[[:space:]]-G[[:space:]]/ /g; s/=-G[[:space:]]/=/g; s/[[:space:]]-G$//g; s/^-G[[:space:]]//g' "$f"
done
echo "=== Saneo anti -G completado ==="

echo "=== Detectando perfil de aprovisionamiento ==="
INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -z "$PROFILE_PATH" ]]; then
  echo "❌ No hay .mobileprovision en $INSTALL_DIR"
  exit 3
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

echo "=== Configurando override de firma en Runner ==="
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

echo "=== Creando export_options.plist ==="
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

echo "=== Ajustando firma en Runner.xcodeproj ==="
PBX="ios/Runner.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY = iPhone Developer/CODE_SIGN_IDENTITY = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY = iOS Development/CODE_SIGN_IDENTITY = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY\\[sdk=iphoneos\\*\\] = iPhone Developer/CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_IDENTITY\\[sdk=iphoneos\\*\\] = iOS Development/CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution/g" "$PBX" || true
/usr/bin/sed -i '' "s/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g" "$PBX" || true

echo "=== Reinstalando Pods antes del archive ==="
pushd ios >/dev/null
pod install
echo "=== Pods listos para archive ==="
popd >/dev/null

echo "=== Iniciando archive ==="
ensure_log_dir
PENDING_XC_LOG="$XC_LOG_PATH"
set +e
xcodebuild -workspace ios/Runner.xcworkspace \
           -scheme Runner \
           -configuration Release \
           -sdk iphoneos \
           -archivePath build/Runner.xcarchive \
           -resultBundlePath "$XC_RESULT_BUNDLE" \
           clean archive \
           | tee "$XC_LOG_PATH"
XC_CMD_STATUS=${PIPESTATUS[0]}
set -e
echo "=== Archive finalizado con código ${XC_CMD_STATUS} ==="

package_logs
print_logs_tree

if [ "$XC_CMD_STATUS" -ne 0 ]; then
  echo "xcodebuild falló con código $XC_CMD_STATUS"
  exit "$XC_CMD_STATUS"
fi

echo "=== Preparando exportación de IPA ==="
rm -rf build/ipa
mkdir -p build/ipa
xcodebuild -exportArchive \
           -archivePath build/Runner.xcarchive \
           -exportOptionsPlist export_options.plist \
           -exportPath build/ipa
echo "=== Exportación de IPA completada ==="

echo "=== Normalizando nombre del IPA ==="
FINAL_IPA="build/ipa/Runner.ipa"
FOUND_IPA="$(find build/ipa -maxdepth 1 -type f -name "*.ipa" | head -n1 || true)"
if [[ -n "$FOUND_IPA" && "$FOUND_IPA" != "$FINAL_IPA" ]]; then
  mv "$FOUND_IPA" "$FINAL_IPA"
fi
echo "=== Verificación de IPA generada ==="

if [[ ! -f "$FINAL_IPA" ]]; then
  echo "❌ No se generó Runner.ipa"
  exit 4
fi

echo "✅ IPA generado en $FINAL_IPA"
print_logs_tree
