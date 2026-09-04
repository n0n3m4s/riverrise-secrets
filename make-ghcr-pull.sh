#!/usr/bin/env bash
# Create ghcr.io imagePullSecret plaintext + seal it for prod.
#
# Usage:
#   ./make-ghcr-pull.sh <github-username> <github-pat>
#   GITHUB_USER=... GITHUB_PAT=... ./make-ghcr-pull.sh
#
# Writes:
#   .local/prod/plain/ghcr-pull.secret.yaml
#   ../k8s/environments/prod/secrets/ghcr-pull.sealed.yaml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="${1:-${GITHUB_USER:-}}"
PAT="${2:-${GITHUB_PAT:-}}"

if [[ -z "$USER_NAME" || -z "$PAT" ]]; then
  echo "usage: $0 <github-username> <github-pat>" >&2
  echo "   or: GITHUB_USER=... GITHUB_PAT=... $0" >&2
  exit 1
fi

AUTH_B64="$(printf '%s:%s' "$USER_NAME" "$PAT" | base64 | tr -d '\n')"
DOCKERCONFIG="$(python3 - "$USER_NAME" "$PAT" "$AUTH_B64" <<'PY'
import json, sys
user, pat, auth = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
  "auths": {
    "ghcr.io": {
      "username": user,
      "password": pat,
      "auth": auth,
    }
  }
}, indent=2))
PY
)"

PLAIN_DIR="$ROOT/.local/prod/plain"
mkdir -p "$PLAIN_DIR"
OUT="$PLAIN_DIR/ghcr-pull.secret.yaml"

# YAML with literal block for dockerconfigjson
python3 - "$OUT" "$DOCKERCONFIG" <<'PY'
from pathlib import Path
import sys
out, cfg = Path(sys.argv[1]), sys.argv[2]
lines = [
  "apiVersion: v1",
  "kind: Secret",
  "metadata:",
  "  name: ghcr-pull",
  "  namespace: default",
  "  annotations:",
  '    argocd.argoproj.io/sync-wave: "-2"',
  "type: kubernetes.io/dockerconfigjson",
  "stringData:",
  "  .dockerconfigjson: |",
]
for line in cfg.splitlines():
  lines.append(f"    {line}")
out.write_text("\n".join(lines) + "\n")
print(f"wrote {out}")
PY
chmod 600 "$OUT"

"$ROOT/encrypt.sh" prod ghcr-pull
echo
echo "OK. Pods need:"
echo "  imagePullSecrets:"
echo "    - name: ghcr-pull"
echo "Images: ghcr.io/${USER_NAME}/<image>:<tag>"
