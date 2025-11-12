#!/bin/bash
set -euo pipefail

LOG_DIR="build/logs"
XC_LOG_PATH="${LOG_DIR}/xcodebuild-archive.log"
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

  tmp_tar="${LOG_DIR}/xcodebuild-archive.tar.gz"
  upper_tar="${LOG_DIR}/../xcodebuild-archive.tar.gz"
  tar -czf "$upper_tar" -C "$LOG_DIR" . 2>/dev/null || true
  mv "$upper_tar" "$tmp_tar" 2>/dev/null || true
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

DIAGNOSTICS_ROOT="${CM_ARTIFACTS:-$PWD/build/diagnostics-fallback}"

ensure_log_dir
mkdir -p build

echo "=== LOGGING PRECOCIDO: Entorno y versiones ==="
( set +e
  xcodebuild -version || true
  swift --version || true
  ruby -v || true
  gem env || true
  pod --version || true
  pod env || true
) > build/logs/toolchain_env.txt 2>&1 || true

echo "=== Limpiando DerivedData (pre-archive) ==="
rm -rf ~/Library/Developer/Xcode/DerivedData/* || true

# Asegura carpeta de logs/artefactos
mkdir -p build/logs/xcconfigs build/logs/scans build/logs/derived || true

# === Diagnóstico de proyectos/schemes ===
echo "=== xcodebuild -list (Runner workspace) ===" | tee build/logs/scans/xcodebuild_list.txt
xcodebuild -workspace ios/Runner.xcworkspace -list >> build/logs/scans/xcodebuild_list.txt 2>&1 || true

echo "=== xcodebuild -list (Pods project) ===" | tee -a build/logs/scans/xcodebuild_list.txt
xcodebuild -project ios/Pods/Pods.xcodeproj -list >> build/logs/scans/xcodebuild_list.txt 2>&1 || true

# === Dump de build settings del target problemático (BoringSSL-GRPC) ===
echo "=== showBuildSettings: Pods BoringSSL-GRPC (Release) ===" | tee build/logs/scans/boringssl_release_buildsettings.txt
xcodebuild -project ios/Pods/Pods.xcodeproj \
  -target "BoringSSL-GRPC" -configuration Release -showBuildSettings \
  >> build/logs/scans/boringssl_release_buildsettings.txt 2>&1 || true

echo "=== showBuildSettings: Pods BoringSSL-GRPC (Debug) ===" | tee build/logs/scans/boringssl_debug_buildsettings.txt
xcodebuild -project ios/Pods/Pods.xcodeproj \
  -target "BoringSSL-GRPC" -configuration Debug -showBuildSettings \
  >> build/logs/scans/boringssl_debug_buildsettings.txt 2>&1 || true

# === Copia de xcconfigs relevantes ===
cp "ios/Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig" \
   "build/logs/xcconfigs/Pods-Runner.release.xcconfig" 2>/dev/null || true
cp "ios/Pods/Target Support Files/BoringSSL-GRPC/BoringSSL-GRPC.release.xcconfig" \
   "build/logs/xcconfigs/BoringSSL-GRPC.release.xcconfig" 2>/dev/null || true
cp "ios/Pods/Target Support Files/BoringSSL-GRPC/BoringSSL-GRPC.debug.xcconfig" \
   "build/logs/xcconfigs/BoringSSL-GRPC.debug.xcconfig" 2>/dev/null || true

# === Grep de flags '-G' y otras rarezas en Pods ===
echo "=== Grep flags sospechosos en ios/Pods ===" | tee build/logs/scans/grep_flags.txt
( grep -R --line-number -E '(^|[[:space:]])-G([[:space:]]|$)' ios/Pods || true ) >> build/logs/scans/grep_flags.txt
( grep -R --line-number -E '(^|[[:space:]])-(ffast-math|fno-exceptions|fno-rtti)([[:space:]]|$)' ios/Pods || true ) >> build/logs/scans/grep_flags.txt

# === Guarda Podfile.lock como artefacto también ===
cp ios/Podfile.lock build/logs/Podfile.lock 2>/dev/null || true

echo "=== Información de entorno ==="
echo "Directorio actual: $PWD"
if command -v xcode-select >/dev/null 2>&1; then
  echo "Xcode path: $(xcode-select -p)"
fi
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version
fi
if command -v clang >/dev/null 2>&1; then
  clang --version | head -n1
fi

echo "=== Build IPA (SansebasStock) ==="

echo "=== Ejecutando flutter clean ==="
flutter clean
echo "=== flutter clean completado ==="

echo "=== Ejecutando flutter pub get ==="
flutter pub get
echo "=== flutter pub get completado ==="

echo "=== Refrescar Pods inicial ==="
(
  set -euo pipefail
  cd ios
  rm -rf Pods Podfile.lock ~/Library/Developer/Xcode/DerivedData
  pod repo update
  pod install --repo-update
)
echo "=== Pods iniciales listos ==="

# Nota: nunca utilizar "-GCC_WARN_INHIBIT_ALL_WARNINGS" como flag de compilador.
#       Debe configurarse mediante el build setting GCC_WARN_INHIBIT_ALL_WARNINGS.
echo "=== Verificando flags '-G' inválidas en .xcconfig de Pods ==="
if grep -R --include="*.xcconfig" -nE '(^|[[:space:]])-G[^[:space:]]*' ios/Pods 2>/dev/null; then
  echo "❌ Se detectaron flags inválidas que comienzan con '-G' en los .xcconfig de Pods."
  echo "   Revisa el post_install del Podfile o los Pods generados."
  exit 65
fi

# === Diagnóstico: recoger artefactos iOS útiles ===
{
  set -e
  if [[ -z "${CM_ARTIFACTS:-}" ]]; then
    echo "⚠️  CM_ARTIFACTS no está definido; se usarán artefactos en ${DIAGNOSTICS_ROOT}."
  fi

  mkdir -p "${DIAGNOSTICS_ROOT}/diagnostics"

  if [ -f ios/Podfile.lock ]; then
    cp -v ios/Podfile.lock "${DIAGNOSTICS_ROOT}/diagnostics/Podfile.lock"
  fi

  if [ -f ios/Runner/Flutter/Release.xcconfig ]; then
    cp -v ios/Runner/Flutter/Release.xcconfig "${DIAGNOSTICS_ROOT}/diagnostics/Release.xcconfig"
  elif [ -f ios/Flutter/Release.xcconfig ]; then
    cp -v ios/Flutter/Release.xcconfig "${DIAGNOSTICS_ROOT}/diagnostics/Release.xcconfig"
  fi

  if [ -f ios/Pods/leveldb-library/port/port.h ]; then
    mkdir -p "${DIAGNOSTICS_ROOT}/diagnostics/leveldb-port"
    cp -v ios/Pods/leveldb-library/port/port.h "${DIAGNOSTICS_ROOT}/diagnostics/leveldb-port/port.h"
  fi

  if [ -f "ios/Pods/Target Support Files/leveldb-library/leveldb-library.release.xcconfig" ]; then
    mkdir -p "${DIAGNOSTICS_ROOT}/diagnostics/leveldb-xcconfig"
    cp -v "ios/Pods/Target Support Files/leveldb-library/leveldb-library.release.xcconfig" \
          "${DIAGNOSTICS_ROOT}/diagnostics/leveldb-xcconfig/leveldb-library.release.xcconfig"
  fi

  if [ -f build/xcodebuild-archive.log ]; then
    cp -v build/xcodebuild-archive.log "${DIAGNOSTICS_ROOT}/diagnostics/xcodebuild-archive.log"
  fi
}

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

echo "=== Iniciando archive ==="
ensure_log_dir
PENDING_XC_LOG="$XC_LOG_PATH"
set +e
(
  set -euo pipefail
  echo "Limpiando DerivedData…"
  rm -rf ~/Library/Developer/Xcode/DerivedData/*

  echo "Limpiando e instalando Pods…"
  pushd ios
    pod deintegrate || true
    pod repo update
    pod install
  popd
)
echo "== Diagnóstico iOS Deployment Target =="
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "build/ios/iphoneos/Runner.app/Info.plist" 2>/dev/null || true
xcodebuild -workspace ios/Runner.xcworkspace \
           -scheme Runner \
           -configuration Release \
           -sdk iphoneos \
           -archivePath build/Runner.xcarchive \
           OTHER_CPLUSPLUSFLAGS='$(OTHER_CPLUSPLUSFLAGS) -stdlib=libc++' \
           archive \
           | tee "$XC_LOG_PATH"
XC_CMD_STATUS=${PIPESTATUS[0]}
set -e
echo "=== Archive finalizado con código ${XC_CMD_STATUS} ==="

echo "=== Intentando capturar response files de clang para BoringSSL-GRPC ==="
DERIVED_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
DD_RUNNER="$(ls -1td "${DERIVED_BASE}/Runner-"*/ 2>/dev/null | head -n1 || true)"
if [[ -n "${DD_RUNNER}" && -d "${DD_RUNNER}" ]]; then
  BORING_DIR="${DD_RUNNER}/Build/Intermediates.noindex/ArchiveIntermediates/Runner/IntermediateBuildFilesPath/Pods.build/Release-iphoneos/BoringSSL-GRPC.build/Objects-normal/arm64"
  if [[ -d "${BORING_DIR}" ]]; then
    cp -v "${BORING_DIR}"/*.resp "build/logs/derived/" 2>/dev/null || true
    cp -v "${BORING_DIR}"/*.d "build/logs/derived/" 2>/dev/null || true
  fi
fi

echo "=== Resumen de artefactos extendidos ==="
find build/logs -maxdepth 3 -type f | sed 's/^/- /' || true

echo "=== Verificando invocaciones a clang sin flags '-G*' ==="
if [[ -f "$XC_LOG_PATH" ]]; then
  found_clang=0
  while IFS= read -r clang_line; do
    [[ -n "$clang_line" ]] || continue
    found_clang=1
    echo "$clang_line"
    if [[ "$clang_line" =~ (^|[[:space:]])-G[A-Za-z] ]]; then
      echo "❌ Se detectó una flag inválida que inicia con '-G' en la invocación a clang."
      exit 66
    fi
  done < <(grep -E "(/|[[:space:]])clang(\+\+)?[[:space:]]" "$XC_LOG_PATH" || true)
  if [[ $found_clang -eq 0 ]]; then
    echo "⚠️  No se localizaron invocaciones directas a clang en el log para validar flags '-G'."
  else
    echo "=== Validación de flags '-G' completada correctamente ==="
  fi
else
  echo "⚠️  No se encontró ${XC_LOG_PATH}; no fue posible validar flags '-G'."
fi

# Guardar el log de xcodebuild del archive
if [ -f /tmp/xcodebuild-archive.log ]; then
  cp -v /tmp/xcodebuild-archive.log "${DIAGNOSTICS_ROOT}/diagnostics/xcodebuild-archive.log"
fi

# Empaquetar todo en un ZIP
if [ -d "${DIAGNOSTICS_ROOT}/diagnostics" ]; then
  (
    cd "${DIAGNOSTICS_ROOT}" &&
    zip -r diagnostics_ios.zip diagnostics || true
  )
fi

head -c 200000 "$XC_LOG_PATH" > build/ios_archive_head.log || true
echo "Fragmento de log guardado en build/ios_archive_head.log"

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
