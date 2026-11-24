#!/usr/bin/env bash
# =================================================================
# Teste ponta a ponta do ambiente local (Docker Compose)
# =================================================================
# 1. sobe PostgreSQL, Moto e os três serviços, esperando o healthcheck;
# 2. roda o teste de integração (scripts/integration/test_fluxo.py);
# 3. com WITH_OTEL=1, confere no log do Collector local os spans dos três
#    serviços e que /health ficou fora dos traces;
# 4. derruba tudo e apaga os volumes, passando ou falhando.
#
# Uso (na raiz do repositório):
#   bash scripts/test-compose.sh
#   WITH_OTEL=1 bash scripts/test-compose.sh
#   PYTHON="py -I" bash scripts/test-compose.sh     # Windows (Git Bash)
# =================================================================
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Interpretador do teste (python3 no Linux/CI; no Windows, PYTHON="py -I").
read -r -a python_cmd <<< "${PYTHON:-python3}"

files=(-f docker-compose.yaml)
if [[ "${WITH_OTEL:-0}" == "1" ]]; then
  files+=(-f docker-compose.otel.yaml)
fi

# Derruba o ambiente em qualquer saída (sucesso, falha ou Ctrl+C). Na falha,
# mostra antes o fim do log dos serviços, para o diagnóstico não se perder.
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "==> Falhou (código ${status}); últimos logs dos serviços:" >&2
    docker compose "${files[@]}" logs --tail 30 aws-init ngo-service donation-service volunteer-service >&2 || true
  fi
  docker compose "${files[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Subindo o ambiente local"
docker compose "${files[@]}" up --build --detach --wait --wait-timeout 300 \
  ngo-service donation-service volunteer-service

echo "==> Teste de integração"
if [[ "${WITH_OTEL:-0}" == "1" ]]; then
  CHECK_TRACEPARENT=1 "${python_cmd[@]}" scripts/integration/test_fluxo.py
else
  "${python_cmd[@]}" scripts/integration/test_fluxo.py
fi

if [[ "${WITH_OTEL:-0}" == "1" ]]; then
  echo "==> Spans no Collector local"
  # O SDK e o Collector exportam em lotes (a cada poucos segundos): em vez de
  # uma espera fixa, tenta por até 30 s até ver os spans dos três serviços.
  missing=(ngo-service donation-service volunteer-service)
  for _ in $(seq 1 15); do
    logs="$(docker compose "${files[@]}" logs otel-collector)"
    still_missing=()
    for svc in "${missing[@]}"; do
      grep -q "service.name: Str(${svc})" <<< "$logs" || still_missing+=("$svc")
    done
    missing=("${still_missing[@]}")
    [[ ${#missing[@]} -eq 0 ]] && break
    sleep 2
  done
  if [[ ${#missing[@]} -ne 0 ]]; then
    echo "FALHOU: nenhum span de ${missing[*]} no Collector" >&2
    exit 1
  fi
  echo "  ok  spans recebidos de ngo-service, donation-service e volunteer-service"
  if grep -q "http.route: Str(/health)" <<< "$logs"; then
    echo "FALHOU: /health apareceu nos traces" >&2
    exit 1
  fi
  echo "  ok  /health fora dos traces"
fi

echo "==> Tudo certo"
