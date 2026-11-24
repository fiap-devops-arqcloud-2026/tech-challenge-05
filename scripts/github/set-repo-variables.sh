#!/usr/bin/env bash
# =================================================================
# VARIABLES DO REPOSITÓRIO a partir das saídas de terraform/base
# =================================================================
# NÃO RODE ANTES DO APPLY DA RAIZ BASE. Sem --dry-run, o script grava
# configuração no GitHub, e os valores só existem depois que a base foi
# aplicada (com plano salvo e autorização do responsável pela conta; ver
# terraform/README.md). Para ver o que ele faria, sem gravar nada, use
# --dry-run.
#
# O que faz: lê cinco saídas da raiz terraform/base, confere o formato e a
# coerência entre elas e grava, com o GitHub CLI, as Variables (não
# Secrets) que os workflows leem em vars.*:
#
#   saída da base           Variable do repositório     quem usa
#   aws_region              AWS_REGION                  publicação no ECR
#   ecr_registry            ECR_REGISTRY                publicação no ECR
#   ci_role_arn             AWS_ROLE_ARN                publicação no ECR (OIDC)
#   self_healing_role_arn   AWS_SELF_HEALING_ROLE_ARN   self-healing (ITSM e AIOps)
#   eks_cluster_name        EKS_CLUSTER_NAME            self-healing (ITSM e AIOps)
#
# Por que Variables e não Secrets: nenhum desses valores é credencial. O
# ARN da role não dá acesso a nada sozinho: a AWS só entrega credencial
# temporária a quem apresenta um token OIDC que o GitHub emite para a main
# deste repositório (trust policy em terraform/modules/iam-ci). Não existe
# chave da AWS para guardar.
#
# Pré-requisitos:
#   - terraform no PATH e a raiz base inicializada com o backend S3:
#       terraform -chdir=terraform/base init -backend-config=backend.hcl -input=false
#     Ler as saídas lê o estado no bucket, com as credenciais AWS da
#     máquina (só leitura).
#   - Sem --dry-run: gh no PATH, autenticado (gh auth login) por alguém
#     com permissão de administrador no repositório.
#
# Uso (na raiz do repositório, no Git Bash ou no Linux):
#   bash scripts/github/set-repo-variables.sh --dry-run    # só mostra o que faria
#   bash scripts/github/set-repo-variables.sh              # grava as cinco Variables
#   bash scripts/github/set-repo-variables.sh --repo dono/repositorio
#
# Saída: 0 quando tudo foi lido e conferido (e gravado, sem --dry-run);
# 1 em erro; 2 em opção inválida. Se alguma saída faltar ou vier fora do
# formato, o script para ANTES de gravar qualquer Variable.
#
# Privacidade: o ID da conta (12 dígitos) aparece mascarado na tela, só com
# os quatro últimos dígitos. O que sai no terminal costuma parar em log e em
# chat, e o repositório é público.
# =================================================================

# -e: aborta no primeiro comando que falhar
# -u: variável não definida vira erro
# -o pipefail: um pipe falha se qualquer etapa falhar
set -euo pipefail

# -----------------------------------------------------------------
# Funções de apoio
# -----------------------------------------------------------------
die() {
  echo "ERRO: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Uso: bash scripts/github/set-repo-variables.sh [--dry-run] [--repo DONO/REPOSITORIO]

Grava as Variables AWS_REGION, ECR_REGISTRY, AWS_ROLE_ARN,
AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME a partir das saídas de
terraform/base. Só faz sentido depois do apply da raiz base.

  --dry-run          lê e confere as saídas e mostra o que seria gravado, sem gravar
  --repo DONO/REPO   repositório de destino (padrão: GH_REPO ou o remote origin)
  -h, --help         mostra esta ajuda
EOF
}

# Mascara o ID da conta: os 12 dígitos viram ******** e os 4 últimos.
mask() {
  sed -E 's/(^|[^0-9])[0-9]{8}([0-9]{4})([^0-9]|$)/\1********\2\3/g' <<<"$1"
}

# Repositório do remote origin, no formato dono/repositorio (só github.com).
repo_from_git() {
  local url
  url="$(git -C "$root_dir" remote get-url origin 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
    https://github.com/*) printf '%s' "${url#https://github.com/}" ;;
    git@github.com:*) printf '%s' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s' "${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
}

# read_output <saída> <variável de destino>
# Lê uma saída da raiz base. -raw devolve o texto puro, sem aspas; em caso
# de erro, a mensagem do próprio terraform aparece antes da nossa.
read_output() {
  local output_name="$1" value
  if ! value="$(terraform -chdir="$tf_dir" output -no-color -raw "$output_name")"; then
    die "não foi possível ler a saída \"${output_name}\" de ${tf_dir}. A base já foi aplicada? O init com o backend foi feito? (terraform -chdir=${tf_dir} init -backend-config=backend.hcl -input=false)"
  fi
  # Um \r no fim (saída de programa do Windows) quebraria a conferência do
  # formato e iria parar na Variable: removido por garantia.
  value="${value%$'\r'}"
  [[ -n "$value" ]] || die "a saída \"${output_name}\" de ${tf_dir} está vazia."
  printf -v "$2" '%s' "$value"
}

# -----------------------------------------------------------------
# Opções
# -----------------------------------------------------------------
dry_run=0
repo="${GH_REPO:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "ERRO: --repo precisa de um valor (dono/repositorio)." >&2; exit 2; }
      repo="$2"
      shift
      ;;
    --repo=*) repo="${1#--repo=}" ;;
    -h | --help) usage; exit 0 ;;
    *) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Raiz do repositório a partir da pasta do script (funciona de qualquer
# diretório e não depende do git). Caminho relativo para o terraform: no
# Git Bash, o terraform.exe não entende caminhos no formato /c/...
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "${script_dir}/../.." && pwd)"
cd "$root_dir"
tf_dir="terraform/base"

[[ -d "$tf_dir" ]] || die "pasta ${tf_dir} não encontrada em ${root_dir}."
command -v terraform >/dev/null 2>&1 || die "terraform não encontrado no PATH."

# -----------------------------------------------------------------
# 1. Repositório de destino
# -----------------------------------------------------------------
if [[ -z "$repo" ]]; then
  repo="$(repo_from_git || true)"
fi
repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
if [[ -n "$repo" && ! "$repo" =~ $repo_re ]]; then
  die "repositório \"${repo}\" fora do formato dono/repositorio."
fi
if [[ -z "$repo" ]]; then
  [[ "$dry_run" -eq 1 ]] || die "não foi possível descobrir o repositório: use --repo dono/repositorio."
  repo="<dono/repositorio>"
fi

# -----------------------------------------------------------------
# 2. Leitura das saídas da base
# -----------------------------------------------------------------
echo "==> Lendo as saídas de ${tf_dir}"
region="" registry="" ci_role_arn="" self_healing_role_arn="" cluster_name=""
read_output aws_region region
read_output ecr_registry registry
read_output ci_role_arn ci_role_arn
read_output self_healing_role_arn self_healing_role_arn
read_output eks_cluster_name cluster_name

# -----------------------------------------------------------------
# 3. Conferência do formato e da coerência, antes de gravar qualquer coisa
# -----------------------------------------------------------------
# Região no formato da AWS (ex.: us-east-2).
region_re='^[a-z]{2}(-[a-z]+)+-[0-9]+$'
[[ "$region" =~ $region_re ]] || die "aws_region fora do formato esperado (ex.: us-east-2)."

# Host do registro: <conta>.dkr.ecr.<região>.amazonaws.com, na mesma região.
registry_re='^([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com$'
[[ "$registry" =~ $registry_re ]] \
  || die "ecr_registry fora do formato <conta>.dkr.ecr.<região>.amazonaws.com."
account_id="${BASH_REMATCH[1]}"
[[ "${BASH_REMATCH[2]}" == "$region" ]] \
  || die "a região do ecr_registry (${BASH_REMATCH[2]}) difere de aws_region (${region})."

# ARNs de role IAM na mesma conta do registro: o CI publica onde assume a role.
role_re='^arn:aws:iam::([0-9]{12}):role/[A-Za-z0-9+=,.@_/-]+$'
for role_output in ci_role_arn self_healing_role_arn; do
  role_value="${!role_output}"
  [[ "$role_value" =~ $role_re ]] || die "${role_output} não é um ARN de role IAM."
  [[ "${BASH_REMATCH[1]}" == "$account_id" ]] \
    || die "${role_output} pertence a outra conta que o ecr_registry."
done

# Nome de cluster EKS: 1 a 100 caracteres, letras, dígitos, - e _.
cluster_re='^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$'
[[ "$cluster_name" =~ $cluster_re ]] || die "eks_cluster_name fora do formato de nome de cluster EKS."

# Ordem fixa de gravação: Variable do GitHub e o valor conferido.
names=(AWS_REGION ECR_REGISTRY AWS_ROLE_ARN AWS_SELF_HEALING_ROLE_ARN EKS_CLUSTER_NAME)
values=("$region" "$registry" "$ci_role_arn" "$self_healing_role_arn" "$cluster_name")
echo "  ok  cinco saídas presentes, no formato esperado e da mesma conta (final ${account_id: -4})"

# -----------------------------------------------------------------
# 4. Gravação (ou só a lista, com --dry-run)
# -----------------------------------------------------------------
if [[ "$dry_run" -eq 1 ]]; then
  echo "==> --dry-run: nada será gravado. Comandos que seriam executados (ID da conta mascarado):"
  for i in "${!names[@]}"; do
    printf "  gh variable set %s --repo %s --body '%s'\n" "${names[$i]}" "$repo" "$(mask "${values[$i]}")"
  done
  exit 0
fi

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) não encontrado no PATH."
gh auth status --hostname github.com >/dev/null 2>&1 \
  || die "o gh não está autenticado em github.com: rode gh auth login."

echo "==> Gravando as Variables em ${repo}"
for i in "${!names[@]}"; do
  # Cria ou atualiza: rodar de novo é seguro e corrige uma gravação parcial.
  gh variable set "${names[$i]}" --repo "$repo" --body "${values[$i]}" >/dev/null \
    || die "falha ao gravar ${names[$i]}; as anteriores já foram gravadas. Rode o script de novo."
  printf '  ok  %s = %s\n' "${names[$i]}" "$(mask "${values[$i]}")"
done

echo "==> Pronto. O próximo push na main publica as imagens no ECR (o job de publicação deixa de ser pulado)."
