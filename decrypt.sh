#!/usr/bin/env bash
# Decrypt SealedSecret → plaintext Secret YAML (offline, with tls.key).
#
# Usage:
#   ./decrypt.sh <env> <name|all>
#
# Reads:  ../k8s/environments/<env>/secrets/<name>.sealed.yaml
# Key:    .local/<env>/tls.key  (or extract from clusters/.../sealed-secrets-key.yaml)
# Writes: .local/<env>/plain/<name>.secret.yaml
set -euo pipefail

ENV="${1:?usage: $0 <prod|staging> <name|all>}"
NAME="${2:?usage: $0 <prod|staging> <name|all>}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
K8S="$(cd "$ROOT/../k8s" && pwd)"
LOCAL_DIR="$ROOT/.local/$ENV"
KEY="$LOCAL_DIR/tls.key"
KEY_SECRET="$ROOT/clusters/$ENV/sealed-secrets/sealed-secrets-key.yaml"
PLAIN_DIR="$LOCAL_DIR/plain"
IN_DIR="$K8S/environments/$ENV/secrets"

mkdir -p "$PLAIN_DIR"
chmod 700 "$PLAIN_DIR" 2>/dev/null || true

if [[ ! -f "$KEY" ]]; then
  if [[ -f "$KEY_SECRET" ]]; then
    python3 - "$KEY_SECRET" "$KEY" <<'PY'
import base64, re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
m = re.search(r"(?m)^\s*tls\.key:\s*(\S+)\s*$", text)
if not m:
    raise SystemExit("tls.key not found in sealed-secrets-key.yaml")
Path(sys.argv[2]).write_bytes(base64.b64decode(m.group(1)))
print(f"extracted key → {sys.argv[2]}")
PY
    chmod 600 "$KEY"
  else
    echo "missing private key: $KEY (run ./generate.sh $ENV or clone secrets repo)" >&2
    exit 1
  fi
fi

if ! command -v kubeseal >/dev/null; then
  echo "kubeseal not found (brew install kubeseal)" >&2
  exit 1
fi

decrypt_one() {
  local name="$1"
  local src="$IN_DIR/${name}.sealed.yaml"
  local dest="$PLAIN_DIR/${name}.secret.yaml"
  local raw="$PLAIN_DIR/.${name}.raw.json"

  if [[ ! -f "$src" ]]; then
    echo "missing sealed: $src" >&2
    return 1
  fi

  kubeseal --recovery-unseal --recovery-private-key "$KEY" --format json < "$src" > "$raw"

  python3 - "$raw" "$dest" <<'PY'
import base64, json, sys
from pathlib import Path

raw_path, dest_path = Path(sys.argv[1]), Path(sys.argv[2])
obj = json.loads(raw_path.read_text())
meta = obj.get("metadata") or {}
meta.pop("ownerReferences", None)
meta.pop("creationTimestamp", None)
meta.pop("resourceVersion", None)
meta.pop("uid", None)
meta.pop("managedFields", None)
annotations = dict(meta.get("annotations") or {})
annotations.setdefault("argocd.argoproj.io/sync-wave", "-2")
meta["annotations"] = annotations

data = obj.get("data") or {}
string_data = {k: base64.b64decode(v).decode("utf-8") for k, v in data.items()}

def q(s: str) -> str:
    if s == "" or s.lower() in ("true", "false", "null") or any(
        c in s for c in [":", "#", "{", "}", "[", "]", ",", "&", "*", "!", "|", ">", "'", '"', "%", "@", "`", "\n"]
    ) or (s[:1].isdigit() if s else False) or (s[:1] in "-?" if s else False):
        return json.dumps(s, ensure_ascii=False)
    return s

lines = [
    "apiVersion: v1",
    "kind: Secret",
    "metadata:",
    f"  name: {meta.get('name', dest_path.stem.replace('.secret',''))}",
]
if meta.get("namespace"):
    lines.append(f"  namespace: {meta['namespace']}")
lines.append("  annotations:")
for ak, av in annotations.items():
    lines.append(f"    {ak}: {q(str(av))}")
lines.append(f"type: {obj.get('type') or 'Opaque'}")
lines.append("stringData:")
for k in sorted(string_data):
    v = string_data[k]
    if "\n" in v:
        lines.append(f"  {k}: |")
        for part in v.splitlines():
            lines.append(f"    {part}")
    else:
        lines.append(f"  {k}: {q(v)}")

dest_path.write_text("\n".join(lines) + "\n")
raw_path.unlink(missing_ok=True)
print(f"decrypted → {dest_path}")
PY
  chmod 600 "$dest"
}

if [[ "$NAME" == "all" ]]; then
  shopt -s nullglob
  files=("$IN_DIR"/*.sealed.yaml)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "no sealed secrets in $IN_DIR" >&2
    exit 1
  fi
  for f in "${files[@]}"; do
    decrypt_one "$(basename "$f" .sealed.yaml)"
  done
else
  decrypt_one "$NAME"
fi

echo
echo "Edit files in $PLAIN_DIR then: ./encrypt.sh $ENV <name|all>"
