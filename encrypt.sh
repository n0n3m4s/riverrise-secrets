#!/usr/bin/env bash
# Encrypt plaintext Secret → SealedSecret in gitops (../k8s).
#
# Usage:
#   ./encrypt.sh <env> <name|all>
#
# Reads:  .local/<env>/plain/<name>.secret.yaml
# Cert:   .local/<env>/tls.crt
# Writes: ../k8s/environments/<env>/secrets/<name>.sealed.yaml
set -euo pipefail

ENV="${1:?usage: $0 <prod|staging> <name|all>}"
NAME="${2:?usage: $0 <prod|staging> <name|all>}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
K8S="$(cd "$ROOT/../k8s" && pwd)"
CERT="$ROOT/.local/$ENV/tls.crt"
PLAIN_DIR="$ROOT/.local/$ENV/plain"
OUT_DIR="$K8S/environments/$ENV/secrets"
KEY_SECRET="$ROOT/clusters/$ENV/sealed-secrets/sealed-secrets-key.yaml"

# Ensure local cert exists (extract from committed Secret if needed)
if [[ ! -f "$CERT" ]]; then
  if [[ -f "$KEY_SECRET" ]]; then
    mkdir -p "$ROOT/.local/$ENV"
    python3 - "$KEY_SECRET" "$CERT" <<'PY'
import base64, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
# data.tls.crt base64 line(s) — support single-line kubectl output
import re
m = re.search(r"(?m)^\s*tls\.crt:\s*(\S+)\s*$", text)
if not m:
    raise SystemExit("tls.crt not found in sealed-secrets-key.yaml")
Path(sys.argv[2]).write_bytes(base64.b64decode(m.group(1)))
print(f"extracted cert → {sys.argv[2]}")
PY
  else
    echo "missing cert: $CERT (run ./generate.sh $ENV)" >&2
    exit 1
  fi
fi

if ! command -v kubeseal >/dev/null; then
  echo "kubeseal not found (brew install kubeseal)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

encrypt_one() {
  local name="$1"
  local src="$PLAIN_DIR/${name}.secret.yaml"
  local dest="$OUT_DIR/${name}.sealed.yaml"
  local tmp="$OUT_DIR/.${name}.sealed.tmp.yaml"

  if [[ ! -f "$src" ]]; then
    echo "missing plaintext: $src" >&2
    echo "  hint: ./decrypt.sh $ENV $name" >&2
    echo "     or: cp examples/$ENV/${name}.secret.example.yaml $src" >&2
    return 1
  fi

  local ns
  ns="$(python3 - "$src" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?ms)^metadata:\n(.*?)(?=^\S)", text + "\n\n")
block = m.group(1) if m else text
nm = re.search(r"(?m)^\s+namespace:\s*[\"']?([A-Za-z0-9-]+)[\"']?\s*$", block)
print(nm.group(1) if nm else "default")
PY
)"

  kubeseal --cert "$CERT" --format yaml < "$src" > "$tmp"

  python3 - "$tmp" "$dest" "$ns" <<'PY'
from pathlib import Path
import sys
tmp, dest, ns = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
text = tmp.read_text()
head, _, rest = text.partition("spec:")
if "namespace:" not in head:
    head = head.replace(
        "metadata:\n  name:",
        f"metadata:\n  namespace: {ns}\n  name:",
        1,
    )
if "argocd.argoproj.io/sync-wave" not in head:
    head = head.replace(
        "metadata:\n",
        "metadata:\n  annotations:\n    argocd.argoproj.io/sync-wave: \"-2\"\n",
        1,
    )
dest.write_text(head + "spec:" + rest)
tmp.unlink(missing_ok=True)
print(f"sealed → {dest} (ns={ns})")
PY
}

if [[ "$NAME" == "all" ]]; then
  shopt -s nullglob
  files=("$PLAIN_DIR"/*.secret.yaml)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "no plaintext secrets in $PLAIN_DIR" >&2
    exit 1
  fi
  for f in "${files[@]}"; do
    encrypt_one "$(basename "$f" .secret.yaml)"
  done
else
  encrypt_one "$NAME"
fi
