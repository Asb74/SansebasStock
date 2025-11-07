#!/usr/bin/env bash
set -Eeuo pipefail

echo "== Setup signing (SansebasStock) =="

need(){ [ -n "${!1:-}" ] || { echo "ERROR: falta $1"; exit 2; }; }

# Requisitos mínimos para hablar con App Store Connect y seleccionar bundle
need APP_STORE_CONNECT_ISSUER_ID
need APP_STORE_CONNECT_KEY_IDENTIFIER
need APP_STORE_CONNECT_PRIVATE_KEY
need APPLE_TEAM_ID
need BUNDLE_ID

# --- Preparar keychain de build ---
keychain initialize
KEYCHAIN_PATH="$(keychain get-default | awk 'END{print $NF}')"
echo "Default keychain: $KEYCHAIN_PATH"
security list-keychains -s "$KEYCHAIN_PATH" login.keychain 2>/dev/null || true
security default-keychain -s "$KEYCHAIN_PATH" || true
security unlock-keychain -p "" "$KEYCHAIN_PATH" || true

# --- Preparar clave privada para 'fetch-signing-files' ---
# 1) Si ya viene en PEM sin passphrase (como en SansebaSms):
if [[ -n "${APPLE_CERTIFICATE_PRIVATE_KEY:-}" ]]; then
  echo "Usando APPLE_CERTIFICATE_PRIVATE_KEY (PEM)…"
  CERT_PEM=/tmp/apple_private_key.pem
  printf '%s\n' "$APPLE_CERTIFICATE_PRIVATE_KEY" > "$CERT_PEM"

# 2) Si viene como P12 + password, la convertimos a PEM (sin passphrase)
elif [[ -n "${CERTIFICATE_P12_BASE64:-}" && -n "${CERTIFICATE_PASSWORD:-}" ]]; then
  echo "Convirtiendo CERTIFICATE_P12_BASE64 a PEM…"
  P12=/tmp/signing.p12
  echo "$CERTIFICATE_P12_BASE64" | base64 --decode > "$P12"
  CERT_PEM=/tmp/apple_private_key.pem
  # extrae la private key sin cifrar (con diagnóstico si falla)
  if ! openssl pkcs12 -in "$P12" -nodes -nocerts -out "$CERT_PEM" -passin pass:"$CERTIFICATE_PASSWORD"; then
    echo "❌ Falló la conversión del P12. Revisa CERTIFICATE_PASSWORD y CERTIFICATE_P12_BASE64."
    exit 3
  fi
  # limpia cabeceras redundantes por si acaso
  awk 'BEGIN{p=0} /BEGIN PRIVATE KEY/{p=1} {if(p)print} /END PRIVATE KEY/{p=0}' "$CERT_PEM" > /tmp/clean.pem && mv /tmp/clean.pem "$CERT_PEM"
else
  echo "❌ Falta APPLE_CERTIFICATE_PRIVATE_KEY (PEM) o CERTIFICATE_P12_BASE64+CERTIFICATE_PASSWORD"
  exit 2
fi

# --- Instalar perfil de aprovisionamiento aportado (opcional) ---
INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$INSTALL_DIR"
if [[ -n "${IOS_PROVISIONING_PROFILE_BASE64:-}" ]]; then
  echo "Instalando perfil desde IOS_PROVISIONING_PROFILE_BASE64…"
  echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$INSTALL_DIR/appstore.mobileprovision"
elif [[ -n "${IOS_APPSTORE_PROFILE_B64:-}" ]]; then
  echo "Instalando perfil desde IOS_APPSTORE_PROFILE_B64…"
  echo "$IOS_APPSTORE_PROFILE_B64" | base64 --decode > "$INSTALL_DIR/appstore.mobileprovision"
else
  echo "No se aportó perfil por variable; se intentará crear/descargar con ASC."
fi

# --- Traer/crear certificados y perfiles desde App Store Connect ---
# La CLI cambió el nombre del flag; detectamos el correcto como en tu flujo original
CERT_FLAG="--certificate-key"
app-store-connect fetch-signing-files --help | grep -q -- "--certificate-key" || CERT_FLAG="--cert-private-key"

app-store-connect fetch-signing-files "$BUNDLE_ID" \
  --type IOS_APP_STORE \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "$APP_STORE_CONNECT_PRIVATE_KEY" \
  $CERT_FLAG "$(<"$CERT_PEM")" \
  --create

# Importar certs y asociar perfiles al proyecto
keychain add-certificates || true
xcode-project use-profiles || true

# 🔎 Diagnóstico de identidades y perfiles
echo "----- Keychains in search list -----"
security list-keychains
echo "----- Identities (codesigning) -----"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
COUNT="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -E 'valid identities found|Valid identities only' | awk '{print $1}' || echo 0)"
if [[ -z "${COUNT:-}" || "${COUNT}" = "0" ]]; then
  echo "❌ No hay identidades de firma válidas visibles en el llavero de build."
  echo "   Revisa CERTIFICATE_P12_BASE64 / CERTIFICATE_PASSWORD o usa APPLE_CERTIFICATE_PRIVATE_KEY (PEM)."
  exit 4
fi

echo "Identidades de firma disponibles:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true

echo "Perfiles disponibles:"
ls -la "$INSTALL_DIR" || true

# --- Aplicar firma MANUAL + UUID del provisioning profile al proyecto (Release) ---
echo "== Enforcing manual signing with installed provisioning profile =="
PBX="ios/Runner.xcodeproj/project.pbxproj"
PROF_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -f "$PROF_PATH" ]]; then
  PROF_UUID="$(/usr/bin/security cms -D -i "$PROF_PATH" | /usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin 2>/dev/null || true)"
  PROF_NAME="$(/usr/bin/security cms -D -i "$PROF_PATH" | /usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin 2>/dev/null || true)"
  echo "Usando profile: ${PROF_NAME:-?} UUID=${PROF_UUID:-?}"
  if [[ -n "${PROF_UUID:-}" && -f "$PBX" ]]; then
    # Forzar CODE_SIGN_STYLE=Manual y asignar DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER y el SPECIFIER para Release/Profile
    /usr/bin/sed -i '' "s/CODE_SIGN_STYLE = Automatic/CODE_SIGN_STYLE = Manual/g" "$PBX"
    /usr/bin/sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]\{10\}/DEVELOPMENT_TEAM = ${APPLE_TEAM_ID}/g" "$PBX"
    /usr/bin/sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID};/g" "$PBX"
    # Ajustar PROVISIONING_PROFILE_SPECIFIER (por UUID, más robusto)
    /usr/bin/sed -i '' "s/PROVISIONING_PROFILE_SPECIFIER = [^;]*;/PROVISIONING_PROFILE_SPECIFIER = ${PROF_UUID};/g" "$PBX"
    # Si no existiera la clave, añadirla en todas las configuraciones Release/Profile iOS
    /usr/bin/perl -0777 -pe "s/(buildSettings = \\{\n)([^}]*?CODE_SIGN_STYLE = Manual;)/\1\2\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = ${PROF_UUID};/g" -i '' "$PBX"
  fi
else
  echo "⚠️ No se localizó .mobileprovision instalado en $INSTALL_DIR"
fi

echo "✅ Setup signing DONE"
