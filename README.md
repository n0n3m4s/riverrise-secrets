# riverrise-secrets (PRIVATE)

Окремий **приватний** git-репозиторій з sealing key для Bitnami Sealed Secrets.
Argo CD Application `sealed-secrets-key` дивиться сюди:

```yaml
# k8s/apps/prod/infra/application-sealed-secrets-key.yaml
repoURL: git@github.com:n0n3m4s/riverrise-secrets.git
path: clusters/prod/sealed-secrets
```

Remote (SSH): `git@github.com:n0n3m4s/riverrise-secrets.git`

## Структура

```text
riverrise-secrets/          # цей репо (локально: sealed-secrets-keys/)
├── clusters/
│   └── prod/sealed-secrets/sealed-secrets-key.yaml   ← синкає Argo
├── examples/prod/          # шаблони Secret
├── .local/prod/            # НЕ в git — tls.key, plain/
├── encrypt.sh / decrypt.sh / generate.sh
└── README.md
```

## Push

```bash
cd sealed-secrets-keys
git remote add origin git@github.com:n0n3m4s/riverrise-secrets.git   # якщо ще немає
git push -u origin main
```

Argo CD: додай репозиторій `git@github.com:n0n3m4s/riverrise-secrets.git` (Credentials) і синкни Application `sealed-secrets-key`.

## GHCR pull secret

```bash
# GitHub → Settings → Developer settings → Personal access tokens
# scopes: read:packages (+ authorize SSO if org)
./make-ghcr-pull.sh <github-user> <PAT>
```

Створює SealedSecret `ghcr-pull` у `k8s/environments/prod/secrets/` (NS `default`).
Сервіси вже мають `imagePullSecrets: [{ name: ghcr-pull }]`.

```bash
./decrypt.sh prod all
$EDITOR .local/prod/plain/api.secret.yaml
./encrypt.sh prod all
# commit SealedSecret у ../k8s/environments/prod/secrets/
```

## Новий sealing key

```bash
./generate.sh prod
git add clusters/prod/sealed-secrets/sealed-secrets-key.yaml
git commit -m "Rotate prod sealed-secrets key"
git push
```

Увага: після ротації треба **перезапечатати** усі SealedSecret новим `tls.crt`.
