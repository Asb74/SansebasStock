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
  # extrae la private key sin cifrar
  openssl pkcs12 -in "$P12" -nodes -nocerts -out "$CERT_PEM" -passin pass:"$CERTIFICATE_PASSWORD" >/dev/null 2>&1
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

# Importar certs al llavero y asociar perfiles al proyecto
keychain add-certificates || true
xcode-project use-profiles

echo "Identidades de firma disponibles:"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true

echo "Perfiles disponibles:"
ls -la "$INSTALL_DIR" || true

echo "✅ Setup signing DONE"
