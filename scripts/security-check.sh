#!/usr/bin/env bash
# =================================================================
# VARREDURA DE SEGREDOS — rodar antes de cada commit e no CI
# =================================================================
# Procura, nos arquivos RASTREADOS pelo Git, padrões que nunca deveriam
# estar versionados. É a última linha de defesa antes de um segredo virar
# histórico público: depois de commitado, apagar do arquivo NÃO apaga do
# histórico (e o repositório é público).
#
# Uso:  bash scripts/security-check.sh
# Saída: 0 quando nada é encontrado; 1 quando alguma regra é violada.
#
# Adaptado da Fase 4 com regras para as chaves dos serviços usados na
# Fase 5 (APM, gestão de incidentes, chat e tokens do GitHub).
# =================================================================

# -e: aborta no primeiro comando que falhar
# -u: variável não definida vira erro, em vez de string vazia
# -o pipefail: o pipe inteiro falha se qualquer etapa falhar
set -euo pipefail

# Sobe para a raiz do repositório, para o script funcionar de qualquer pasta.
root_dir="$(git rev-parse --show-toplevel)"
cd "$root_dir"

# Acumulador: vira 1 na primeira regra violada e decide o código de saída.
failed=0

# -----------------------------------------------------------------
# check <descrição> <expressão regular>
# Procura o padrão no conteúdo dos arquivos que podem ir para o Git.
# -----------------------------------------------------------------
check() {
  local description="$1"
  local pattern="$2"

  # git grep com --untracked varre os arquivos rastreados E os novos ainda
  # não adicionados, respeitando o .gitignore: o segredo é pego antes do
  # "git add", não só depois do commit.
  #   -I  ignora binários       -n  mostra o número da linha
  #   -E  regex estendida
  # Exclusões: este script (contém os próprios padrões) e arquivos de
  # exemplo (*.example), que existem para mostrar o formato de um valor.
  # Código de saída do git grep: 0 = achou, 1 = não achou, >1 = erro (ex.:
  # regex inválida). O erro precisa reprovar: sem isso, uma regra quebrada
  # "passaria" em silêncio e o verificador deixaria de verificar.
  local status=0
  git grep --untracked -InE "$pattern" -- \
      ':!scripts/security-check.sh' \
      ':(exclude,glob)**/*.example' \
      ':(exclude,glob)**/*.example.*' || status=$?
  if [[ "$status" -eq 0 ]]; then
    echo "[ERRO] ${description}"
    failed=1
  elif [[ "$status" -gt 1 ]]; then
    echo "[ERRO] Falha ao executar a regra (código ${status}): ${description}"
    failed=1
  fi
}

# -----------------------------------------------------------------
# check_file <descrição> <pathspec>
# Falha se algum arquivo rastreado (ou novo e não ignorado) casar com o
# nome proibido.
# -----------------------------------------------------------------
check_file() {
  local description="$1"
  shift
  local found
  # ls-files --cached --others --exclude-standard: rastreados + novos que o
  # .gitignore não cobre, ou seja, tudo o que um "git add" poderia levar.
  found="$(git ls-files --cached --others --exclude-standard -- "$@")"
  if [[ -n "$found" ]]; then
    echo "$found"
    echo "[ERRO] ${description}"
    failed=1
  fi
}

# -----------------------------------------------------------------
# REGRAS DE CONTEÚDO
# -----------------------------------------------------------------

# Chave de acesso da AWS: AKIA (permanente) ou ASIA (temporária) + 16 maiúsculas.
check "Possível chave de acesso da AWS" '(AKIA|ASIA)[0-9A-Z]{16}'

# Cabeçalho de chave privada (RSA, EC, OpenSSH ou PKCS#8).
check "Possível chave privada" 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY'

# Tokens do GitHub: clássicos (ghp_, gho_, ghs_...) e fine-grained (github_pat_).
check "Possível token do GitHub" '(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'

# Chaves do New Relic: license key de ingestão (termina em NRAL) e user key (NRAK-).
check "Possível chave do New Relic" '([0-9a-fA-F]{36}NRAL|NRAK-[A-Z0-9]{27})'

# Webhook do Slack: a URL inteira é a credencial.
check "Possível webhook do Slack" 'hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+'

# Atribuição direta de valor longo a uma variável de segredo conhecida
# (ex.: AWS_SECRET_ACCESS_KEY=wJalr... em .env ou YAML).
check "Atribuição suspeita de segredo" \
  '(AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|GITHUB_TOKEN|NEW_RELIC_LICENSE_KEY|PAGERDUTY_ROUTING_KEY|SLACK_WEBHOOK_URL)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{20,}'

# ID de conta AWS (12 dígitos isolados). O repositório é público: o ID real
# da conta fica só em arquivos locais ignorados (tfvars, backend.hcl).
# Permitidos, por serem fictícios e públicos: 000000000000 (exemplos e
# testes) e 123456789012 (conta padrão do emulador Moto). Lockfiles e go.sum
# ficam de fora porque seus hashes podem conter sequências de dígitos.
# Exceção única para o ID real: o endereço do ECR (<conta>.dkr.ecr.<região>)
# dentro de gitops/, que o robô do CI grava no overlay a cada imagem
# publicada. A AWS não trata o ID de conta como segredo, o acesso continua
# protegido por IAM e OIDC, e o Kustomize não permite separar o registro da
# tag (um override só de nome apaga a tag). Em qualquer outro lugar, reprova.
check_account_ids() {
  local status=0 matches offending
  matches="$(git grep --untracked -InE '(^|[^0-9A-Za-z])[0-9]{12}([^0-9A-Za-z]|$)' -- \
      ':!scripts/security-check.sh' \
      ':(exclude,glob)**/.terraform.lock.hcl' \
      ':(exclude,glob)**/go.sum')" || status=$?
  if [[ "$status" -gt 1 ]]; then
    echo "[ERRO] Falha ao executar a regra de ID de conta (código ${status})"
    failed=1
    return
  fi
  # Mantém só as linhas com algum número de 12 dígitos fora da lista
  # permitida. Cada linha do git grep começa com "caminho:linha:", o que
  # permite restringir a exceção do ECR à pasta gitops/.
  offending="$(awk '{
      line = $0
      while (match(line, /(^|[^0-9A-Za-z])[0-9]{12}([^0-9A-Za-z]|$)/)) {
        token = substr(line, RSTART, RLENGTH)
        rest = substr(line, RSTART)
        gsub(/[^0-9]/, "", token)
        ecr_no_gitops = ($0 ~ /^gitops\//) && (rest ~ /^[^0-9A-Za-z]?[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\.dkr\.ecr\./)
        if (token != "000000000000" && token != "123456789012" && !ecr_no_gitops) { print $0; break }
        line = substr(line, RSTART + RLENGTH - 1)
      }
    }' <<< "$matches")"
  if [[ -n "$offending" ]]; then
    echo "$offending"
    echo "[ERRO] Possível ID real de conta AWS (use 000000000000 em exemplos)"
    failed=1
  fi
}
check_account_ids

# -----------------------------------------------------------------
# REGRAS DE ARQUIVO
# -----------------------------------------------------------------
check_file "Arquivo .env fora do .gitignore (use .env.example com valores fictícios)" \
  ':(glob)**/.env' ':(glob)**/.env.*' ':(exclude,glob)**/.env.example'
check_file "Estado ou plano do Terraform fora do .gitignore" \
  ':(glob)**/*.tfstate' ':(glob)**/*.tfstate.*' ':(glob)**/*.tfplan' ':(glob)**/*.tfplan.json'
check_file "tfvars ou backend.hcl reais fora do .gitignore" \
  ':(glob)**/*.tfvars' ':(glob)**/*.tfvars.json' ':(glob)**/backend.hcl' ':(glob)**/*.backend.hcl'
check_file "kubeconfig, certificado ou chave fora do .gitignore" \
  ':(glob)**/kubeconfig' ':(glob)**/*.kubeconfig' ':(glob)**/*.pem' ':(glob)**/*.key' ':(glob)**/*.p12' ':(glob)**/*.pfx'

# -----------------------------------------------------------------
# RESULTADO
# -----------------------------------------------------------------
# Sair com 1 faz o CI marcar o job como vermelho e interrompe scripts com set -e.
if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Verificação concluída: nenhum segredo conhecido nem arquivo proibido encontrado."
