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

# --- Forzar firma manual con el profile instalado (specifier=Name, uuid=UUID) ---
echo "== Enforcing manual signing with installed provisioning profile =="
PBX="ios/Runner.xcodeproj/project.pbxproj"
PROF_PATH="$(ls "$INSTALL_DIR"/*.mobileprovision 2>/dev/null | head -n1 || true)"
if [[ -f "$PROF_PATH" ]]; then
  TMP_PLIST="$(mktemp /tmp/profile.XXXXXX.plist)"
  /usr/bin/security cms -D -i "$PROF_PATH" > "$TMP_PLIST"
  PROF_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$TMP_PLIST" 2>/dev/null || true)"
  PROF_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMP_PLIST" 2>/dev/null || true)"
  rm -f "$TMP_PLIST"
  echo "Usando profile: NAME='${PROF_NAME:-?}'  UUID='${PROF_UUID:-?}'"
  if [[ -n "${PROF_NAME:-}" && -n "${PROF_UUID:-}" && -f "$PBX" ]]; then
    python3 - "$PBX" "$APPLE_TEAM_ID" "$BUNDLE_ID" "$PROF_NAME" "$PROF_UUID" <<'PY'
import re
import sys

path, team, bundle, prof_name, prof_uuid = sys.argv[1:]

with open(path, 'r', encoding='utf-8') as fh:
    lines = fh.readlines()

result = []
inside = False
settings_indent = ''
seen_manual = False
has_spec = False
has_uuid = False

for line in lines:
    stripped = line.strip()

    if stripped == 'buildSettings = {':
        inside = True
        block_indent = line[:len(line) - len(line.lstrip(' \t'))]
        settings_indent = f"{block_indent}\t"
        seen_manual = False
        has_spec = False
        has_uuid = False
        result.append(line)
        continue

    if inside:
        indent = line[:len(line) - len(line.lstrip(' \t'))]

        if stripped.startswith('CODE_SIGN_STYLE ='):
            line = f"{indent}CODE_SIGN_STYLE = Manual;\n"
            seen_manual = True
        elif stripped.startswith('DEVELOPMENT_TEAM ='):
            line = f"{indent}DEVELOPMENT_TEAM = {team};\n"
        elif stripped.startswith('PRODUCT_BUNDLE_IDENTIFIER ='):
            line = f"{indent}PRODUCT_BUNDLE_IDENTIFIER = {bundle};\n"
        elif stripped.startswith('PROVISIONING_PROFILE_SPECIFIER ='):
            line = f"{indent}PROVISIONING_PROFILE_SPECIFIER = \"{prof_name}\";\n"
            has_spec = True
        elif stripped.startswith('PROVISIONING_PROFILE ='):
            line = f"{indent}PROVISIONING_PROFILE = \"{prof_uuid}\";\n"
            has_uuid = True
        elif stripped == '};':
            if seen_manual:
                if not has_spec:
                    result.append(f"{settings_indent}PROVISIONING_PROFILE_SPECIFIER = \"{prof_name}\";\n")
                    has_spec = True
                if not has_uuid:
                    result.append(f"{settings_indent}PROVISIONING_PROFILE = \"{prof_uuid}\";\n")
                    has_uuid = True
            inside = False
            result.append(line)
            continue

        result.append(line)
        continue

    if 'CODE_SIGN_STYLE = Automatic;' in line:
        line = line.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual;')

    if 'DEVELOPMENT_TEAM = ' in line:
        line = re.sub(r'DEVELOPMENT_TEAM = [A-Z0-9]{10}', f'DEVELOPMENT_TEAM = {team}', line)

    if 'PRODUCT_BUNDLE_IDENTIFIER = ' in line:
        line = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};', line)

    result.append(line)

with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(result)
PY
  else
    echo "⚠️ No se pudo extraer Name/UUID del profile."
  fi
else
  echo "⚠️ No se localizó .mobileprovision en $INSTALL_DIR"
fi

