#!/usr/bin/env bash
# =================================================================
# Validação offline dos manifestos GitOps (local e no CI)
# =================================================================
# Confere, sem cluster e sem credencial:
#   1. as cópias dos SQL do Job de schema batem com services/*/db/init.sql;
#   2. o overlay renderiza com o MESMO Kustomize do ArgoCD 3.6.2 (5.8.3);
#   3. nada que a raiz terraform/k8s cria aparece no GitOps (Namespace,
#      Secret, ServiceAccount, StorageClass e o ConfigMap aws-endpoints):
#      dois donos para o mesmo objeto fariam ArgoCD e Terraform brigarem;
#   4. o YAML renderizado passa no schema do Kubernetes (kubeconform, estrito);
#   5. boas práticas (kube-linter: não root, disco somente leitura, recursos,
#      seletores, PDB...), com as exceções justificadas em gitops/.kube-linter.yaml;
#   6. os scripts shell do GitOps passam no shellcheck.
#
# Uso (na raiz do repositório, com Docker):  bash scripts/gitops/validate.sh
# Saída: 0 quando tudo passa; diferente de 0 na primeira falha.
# =================================================================
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "$root_dir"

# Versões fixadas: as mesmas em qualquer máquina e no CI.
KUSTOMIZE_IMAGE="registry.k8s.io/kustomize/kustomize:v5.8.3" # a do ArgoCD 3.6.2
KUBECONFORM_IMAGE="ghcr.io/yannh/kubeconform:v0.8.0"
KUBE_LINTER_IMAGE="stackrox/kube-linter:v0.8.3"
SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0"
# O repositório de schemas do kubeconform vai até o Kubernetes 1.34. Os
# objetos usados aqui (Deployment, Service, PDB, Job, ConfigMap) têm APIs
# estáveis, iguais na 1.37 do cluster.
KUBERNETES_SCHEMA_VERSION="1.34.12"

# No Git Bash (Windows), o Docker precisa do caminho no formato C:/...; e o
# MSYS não pode converter os caminhos /repo e /work dos contêineres.
export MSYS_NO_PATHCONV=1
host_path() {
  if pwd -W >/dev/null 2>&1; then (cd "$1" && pwd -W); else (cd "$1" && pwd); fi
}

work_dir="${root_dir}/tmp/gitops-validate"
rm -rf "$work_dir"
mkdir -p "$work_dir"
rendered="${work_dir}/prod.yaml"
repo_host="$(host_path "$root_dir")"
work_host="$(host_path "$work_dir")"

echo "==> 1. Cópias dos SQL do Job de schema"
cmp services/ngo-service/db/init.sql gitops/base/db-schema/sql/ngo_db.sql
cmp services/donation-service/db/init.sql gitops/base/db-schema/sql/donation_db.sql
echo "  ok  sql/ngo_db.sql e sql/donation_db.sql idênticos aos originais"

echo "==> 2. Render do overlay de produção (Kustomize 5.8.3)"
docker run --rm -v "${repo_host}:/repo:ro" "$KUSTOMIZE_IMAGE" build /repo/gitops/overlays/prod > "$rendered"
echo "  ok  $(grep -c '^kind:' "$rendered") objetos renderizados"

echo "==> 3. Objetos que pertencem ao Terraform não podem estar no GitOps"
proibidos="$(awk '
  /^---/ { kind = ""; name = ""; meta = 0; next }
  /^kind: / { kind = $2 }
  /^metadata:/ { meta = 1; next }
  meta && /^  name: / { name = $2; meta = 0 }
  /^[a-z]/ && !/^metadata:/ { meta = 0 }
  kind != "" && name != "" {
    if (kind ~ /^(Namespace|Secret|ServiceAccount|StorageClass)$/ || (kind == "ConfigMap" && name == "aws-endpoints")) print kind "/" name
    kind = ""; name = ""
  }' "$rendered")"
if [[ -n "$proibidos" ]]; then
  echo "$proibidos" >&2
  echo "FALHOU: objetos criados pela raiz terraform/k8s apareceram no GitOps" >&2
  exit 1
fi
echo "  ok  nenhum Namespace, Secret, ServiceAccount, StorageClass ou ConfigMap aws-endpoints"

echo "==> 4. Schema do Kubernetes (kubeconform -strict, ${KUBERNETES_SCHEMA_VERSION})"
docker run --rm -i "$KUBECONFORM_IMAGE" -strict -summary -kubernetes-version "$KUBERNETES_SCHEMA_VERSION" - < "$rendered"

echo "==> 5. Boas práticas (kube-linter)"
cp gitops/.kube-linter.yaml "${work_dir}/kube-linter.yaml"
docker run --rm -v "${work_host}:/work:ro" "$KUBE_LINTER_IMAGE" lint --config /work/kube-linter.yaml /work/prod.yaml

echo "==> 6. Scripts shell do GitOps (shellcheck)"
docker run --rm -v "${repo_host}:/repo:ro" -w /repo "$SHELLCHECK_IMAGE" --shell=sh \
  gitops/base/db-schema/apply.sh gitops/base/traffic-generator/gerar-trafego.sh
echo "  ok  shellcheck sem achados"

echo "==> GitOps válido"
