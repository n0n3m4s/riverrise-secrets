# riverrise-secrets (PRIVATE)

Окремий **приватний** git-репозиторій з sealing key для Bitnami Sealed Secrets.
Argo CD Application `sealed-secrets-key` дивиться сюди:

```yaml
# k8s/apps/prod/infra/application-sealed-secrets-key.yaml
repoURL: https://github.com/<ORG>/riverrise-secrets.git
path: clusters/prod/sealed-secrets
```

## Структура

```text
riverrise-secrets/          # цей репо (локально: sealed-secrets-keys/)
├── clusters/
│   ├── prod/sealed-secrets/sealed-secrets-key.yaml   ← синкає Argo
│   └── staging/sealed-secrets/
├── examples/prod/          # шаблони Secret
├── .local/<env>/           # НЕ в git — tls.key, plain/
├── encrypt.sh / decrypt.sh / generate.sh
└── README.md
```

## Перший пуш

```bash
cd sealed-secrets-keys   # або clone після rename
git init
git add .
git status   # має бути clusters/prod/sealed-secrets/sealed-secrets-key.yaml
git commit -m "Add prod sealed-secrets key for Argo CD"
gh repo create riverrise-secrets --private --source=. --remote=origin --push
# або:
# git remote add origin git@github.com:ORG/riverrise-secrets.git
# git branch -M main
# git push -u origin main
```

Після пушу підстав реальний `repoURL` у `k8s/apps/prod/infra/application-sealed-secrets-key.yaml`
і додай репо в Argo CD (Settings → Repositories) з read-доступом.

## Робота з app-секретами (gitops k8s)

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
