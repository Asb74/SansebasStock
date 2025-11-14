#!/usr/bin/env bash
set -euo pipefail

echo "=== Setup iOS code signing ==="

WORK_DIR="$HOME/codemagic_signing"
mkdir -p "$WORK_DIR"

CERT_P12_PATH="$WORK_DIR/certificate.p12"
PROFILE_PATH="$WORK_DIR/profile.mobileprovision"
KEYCHAIN_NAME="build.keychain"

echo "Decodificando certificado P12..."
echo "$CERTIFICATE_P12_BASE64" | base64 --decode > "$CERT_P12_PATH"
ls -lh "$CERT_P12_PATH"

echo "Decodificando provisioning profile..."
echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"
ls -lh "$PROFILE_PATH"

echo "Creando keychain temporal..."
security create-keychain -p "" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 21600 "$KEYCHAIN_NAME"
security unlock-keychain -p "" "$KEYCHAIN_NAME"

echo "Configurando keychain por defecto..."
security list-keychains -s "$KEYCHAIN_NAME"
security default-keychain -s "$KEYCHAIN_NAME"

echo "Importando certificado en el keychain..."
security import "$CERT_P12_PATH" \
  -k "$KEYCHAIN_NAME" \
  -P "$CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "Instalando provisioning profile..."
PP_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PP_DIR"

UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' /dev/stdin <<< "$(security cms -D -i "$PROFILE_PATH")")
cp "$PROFILE_PATH" "$PP_DIR/$UUID.mobileprovision"

echo "Provisioning profile UUID: $UUID"
echo "Keychain: $KEYCHAIN_NAME listo para usar."
