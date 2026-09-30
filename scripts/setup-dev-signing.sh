#!/usr/bin/env bash
# Cria (uma vez) o certificado local "boringCode Dev" no chaveiro de login.
#
# Por quê: com assinatura ad-hoc ("-") a identidade do app é o hash do binário, que muda a cada
# build — o macOS trata cada build como um app novo e pede Acessibilidade/Automação de novo.
# Assinando sempre com o mesmo certificado, a identidade fica estável e as permissões ficam.
#
# É só para desenvolvimento nesta máquina: não é Developer ID, não serve para distribuir e não
# mexe em confiança do sistema. Para remover: Acesso às Chaves › login › "boringCode Dev".
set -euo pipefail

NAME="boringCode Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ Certificado \"$NAME\" já existe."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# LibreSSL do sistema: gera um .p12 que o `security import` aceita sem flags extras.
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(uuidgen)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout "pass:$PASS"

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "✓ Certificado \"$NAME\" criado no chaveiro de login."
