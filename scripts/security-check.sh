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
# Procura o padrão no conteúdo dos arquivos rastreados.
# -----------------------------------------------------------------
check() {
  local description="$1"
  local pattern="$2"

  # git grep varre só arquivos rastreados (o que está no .gitignore não sobe).
  #   -I  ignora binários       -n  mostra o número da linha
  #   -E  regex estendida
  # Exclusões: este script (contém os próprios padrões) e arquivos de
  # exemplo (*.example), que existem para mostrar o formato de um valor.
  # Código de saída do git grep: 0 = achou, 1 = não achou, >1 = erro (ex.:
  # regex inválida). O erro precisa reprovar: sem isso, uma regra quebrada
  # "passaria" em silêncio e o verificador deixaria de verificar.
  local status=0
  git grep -InE "$pattern" -- \
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
# Falha se algum arquivo rastreado casar com o nome proibido.
# -----------------------------------------------------------------
check_file() {
  local description="$1"
  shift
  local found
  # ls-files devolve os arquivos rastreados que casam com os pathspecs.
  found="$(git ls-files -- "$@")"
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

# -----------------------------------------------------------------
# REGRAS DE ARQUIVO
# -----------------------------------------------------------------
check_file "Arquivo .env rastreado (use .env.example com valores fictícios)" \
  ':(glob)**/.env' ':(glob)**/.env.*' ':(exclude,glob)**/.env.example'
check_file "Estado ou plano do Terraform rastreado" \
  ':(glob)**/*.tfstate' ':(glob)**/*.tfstate.*' ':(glob)**/*.tfplan' ':(glob)**/*.tfplan.json'
check_file "tfvars ou backend.hcl reais rastreados" \
  ':(glob)**/*.tfvars' ':(glob)**/*.tfvars.json' ':(glob)**/backend.hcl' ':(glob)**/*.backend.hcl'
check_file "kubeconfig, certificado ou chave rastreados" \
  ':(glob)**/kubeconfig' ':(glob)**/*.kubeconfig' ':(glob)**/*.pem' ':(glob)**/*.key' ':(glob)**/*.p12' ':(glob)**/*.pfx'

# -----------------------------------------------------------------
# RESULTADO
# -----------------------------------------------------------------
# Sair com 1 faz o CI marcar o job como vermelho e interrompe scripts com set -e.
if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Verificação concluída: nenhum segredo conhecido nem arquivo proibido encontrado."
