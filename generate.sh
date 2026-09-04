#!/usr/bin/env bash
# Generate Bitnami Sealed Secrets TLS keypair for an env (prod|staging).
# Writes:
#   clusters/<env>/sealed-secrets/sealed-secrets-key.yaml  ← Argo CD syncs this
#   .local/<env>/tls.{crt,key}                             ← local encrypt/decrypt
#
# Usage: ./generate.sh prod
set -euo pipefail

ENV="${1:?usage: $0 <prod|staging>}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_DIR="$ROOT/clusters/$ENV/sealed-secrets"
LOCAL_DIR="$ROOT/.local/$ENV"

mkdir -p "$CLUSTER_DIR" "$LOCAL_DIR/plain"

openssl req -x509 -days 3650 -newkey rsa:4096 -nodes \
  -keyout "$LOCAL_DIR/tls.key" \
  -out "$LOCAL_DIR/tls.crt" \
  -subj "/CN=sealed-secrets/O=riverrise/OU=$ENV"

chmod 600 "$LOCAL_DIR/tls.key"

kubectl create secret tls sealed-secrets-key \
  --cert="$LOCAL_DIR/tls.crt" \
  --key="$LOCAL_DIR/tls.key" \
  -n sealed-secrets \
  --dry-run=client -o yaml \
| kubectl label --local -f - \
    sealedsecrets.bitnami.com/sealed-secrets-key=active \
    -o yaml > "$CLUSTER_DIR/sealed-secrets-key.yaml"

echo
echo "OK:"
echo "  Argo path: $CLUSTER_DIR/sealed-secrets-key.yaml"
echo "  Local:     $LOCAL_DIR/tls.{crt,key}"
echo
echo "Commit & push this repo (PRIVATE), then Argo Application path:"
echo "  clusters/$ENV/sealed-secrets"
echo
echo "Seal app secrets:"
echo "  ./encrypt.sh $ENV <name|all>"
