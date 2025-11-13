#!/usr/bin/env bash
set -euo pipefail

echo "=== Build IPA (Flutter) ==="

flutter --version
echo "Running flutter pub get..."
flutter pub get

echo "Cleaning previous builds..."
flutter clean

echo "Building IPA (release, con firma)..."
# No usar --no-codesign para que Codemagic pueda firmar
flutter build ipa --release

echo "Buscando IPA generada..."
IPA_PATH=$(find build/ios/ipa -maxdepth 1 -name "*.ipa" | head -n 1 || true)

if [ -z "$IPA_PATH" ]; then
  echo "❌ No se encontró ninguna IPA en build/ios/ipa"
  ls -R build/ios || true
  exit 1
fi

echo "✅ IPA generada en: $IPA_PATH"

# Copiar al directorio estándar de artefactos de Codemagic
mkdir -p "$CM_ARTIFACTS"
cp "$IPA_PATH" "$CM_ARTIFACTS/"

echo "Artefactos copiados a $CM_ARTIFACTS"
