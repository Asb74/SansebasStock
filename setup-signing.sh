#!/usr/bin/env bash
set -Eeuo pipefail

echo "== Setup signing (SansebasStock) =="

need(){ [ -n "${!1:-}" ] || { echo "ERROR: falta $1"; exit 2; }; }
need APP_STORE_CONNECT_ISSUER_ID
need APP_STORE_CONNECT_KEY_IDENTIFIER
need APP_STORE_CONNECT_PRIVATE_KEY
need APPLE_TEAM_ID
need BUNDLE_ID

# --- Keychain de build ---
keychain initialize
KEYCHAIN_PATH="$(keychain get-default | awk 'END{print $NF}')"
echo "Default keychain: $KEYCHAIN_PATH"
security list-keychains -s "$KEYCHAIN_PATH" login.keychain 2>/dev/null || true
security default-keychain -s "$KEYCHAIN_PATH" || true
security unlock-keychain -p "" "$KEYCHAIN_PATH" || true

# --- Clave privada para ASC (PEM o P12) ---
if [[ -n "${APPLE_CERTIFICATE_PRIVATE_KEY:-}" ]]; then
  echo "Usando APPLE_CERTIFICATE_PRIVATE_KEY (PEM)…"
  CERT_PEM=/tmp/apple_private_key.pem
  printf '%s\n' "$APPLE_CERTIFICATE_PRIVATE_KEY" > "$CERT_PEM"
elif [[ -n "${CERTIFICATE_P12_BASE64:-}" && -n "${CERTIFICATE_PASSWORD:-}" ]]; then
  echo "Convirtiendo CERTIFICATE_P12_BASE64 a PEM…"
  P12=/tmp/signing.p12
  echo "$CERTIFICATE_P12_BASE64" | base64 --decode > "$P12"
  CERT_PEM=/tmp/apple_private_key.pem
  if ! openssl pkcs12 -in "$P12" -nodes -nocerts -out "$CERT_PEM" -passin pass:"$CERTIFICATE_PASSWORD"; then
    echo "❌ Falló la conversión del P12. Revisa CERTIFICATE_PASSWORD y CERTIFICATE_P12_BASE64."
    exit 3
  fi
  awk 'BEGIN{p=0} /BEGIN PRIVATE KEY/{p=1} {if(p)print} /END PRIVATE KEY/{p=0}' "$CERT_PEM" > /tmp/clean.pem
  mv /tmp/clean.pem "$CERT_PEM"
else
  echo "❌ Falta APPLE_CERTIFICATE_PRIVATE_KEY (PEM) o CERTIFICATE_P12_BASE64+CERTIFICATE_PASSWORD"
  exit 2
fi

# --- Perfil local (opcional, por variable) ---
INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$INSTALL_DIR"
if [[ -n "${IOS_PROVISIONING_PROFILE_BASE64:-}" ]]; then
  echo "Instalando perfil desde IOS_PROVISIONING_PROFILE_BASE64…"
  echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$INSTALL_DIR/appstore.mobileprovision"
elif [[ -n "${IOS_APPSTORE_PROFILE_B64:-}" ]]; then
  echo "Instalando perfil desde IOS_APPSTORE_PROFILE_B64…"
  echo "$IOS_APPSTORE_PROFILE_B64" | base64 --decode > "$INSTALL_DIR/appstore.mobileprovision"
fi

# --- Descargar/crear desde App Store Connect ---
CERT_FLAG="--certificate-key"
app-store-connect fetch-signing-files --help | grep -q -- "--certificate-key" || CERT_FLAG="--cert-private-key"

app-store-connect fetch-signing-files "$BUNDLE_ID" \
  --type IOS_APP_STORE \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "$APP_STORE_CONNECT_PRIVATE_KEY" \
  $CERT_FLAG "$(<"$CERT_PEM")" \
  --create

# Importar y aplicar
keychain add-certificates || true
# Ensure the imported certificates are usable by Xcode tools
if [[ -n "${KEYCHAIN_PATH:-}" && -f "$KEYCHAIN_PATH" ]]; then
  security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
fi
# xcode-project use-profiles || true

echo "----- Keychains in search list -----"
security list-keychains
echo "----- Identities (codesigning) -----"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
COUNT="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -E 'valid identities found|Valid identities only' | awk '{print $1}' || echo 0)"
if [[ -z "${COUNT:-}" || "${COUNT}" = "0" ]]; then
  echo "❌ No hay identidades de firma válidas visibles."
  exit 4
fi

echo "Perfiles disponibles:"
ls -la "$INSTALL_DIR" || true
echo "✅ Setup signing DONE"
