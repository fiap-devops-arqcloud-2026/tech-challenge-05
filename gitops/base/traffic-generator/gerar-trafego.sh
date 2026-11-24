#!/bin/sh
# =================================================================
# Gerador de tráfego sintético da SolidaryTech
# =================================================================
# Simula o uso real da plataforma dentro do cluster, para alimentar as
# métricas, o SLO do donation-service e a detecção de anomalias do APM (que
# precisa de histórico de tráfego estável antes de detectar desvios).
#
# A cada volta: uma doação (hot path) e, de tempos em tempos, as consultas
# de ONGs e doações e o cadastro e consulta de voluntários. Só payloads
# válidos: erro aqui é sinal de problema na plataforma, não no gerador.
# Liga e desliga pelo número de réplicas no Git (0 ou 1).
#
# Variáveis: INTERVALO_SEGUNDOS (padrão 1), NGO_ID (padrão 1, a primeira
# ONG do seed do coordenador) e as URLs dos três serviços.
# =================================================================
set -u

INTERVALO="${INTERVALO_SEGUNDOS:-1}"
NGO_ID="${NGO_ID:-1}"
NGO_URL="${NGO_URL:-http://ngo-service:8081}"
DONATION_URL="${DONATION_URL:-http://donation-service:8082}"
VOLUNTEER_URL="${VOLUNTEER_URL:-http://volunteer-service:8083}"

# requisicao <método> <url> [corpo JSON]: imprime só o código HTTP.
# --max-time evita que um serviço lento trave o gerador.
requisicao() {
  if [ -n "${3:-}" ]; then
    curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -X "$1" \
      -H 'Content-Type: application/json' -d "$3" "$2" 2>/dev/null || echo "000"
  else
    curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -X "$1" "$2" 2>/dev/null || echo "000"
  fi
}

volta=0
ok=0
falhas=0
while true; do
  volta=$((volta + 1))
  # Valor da doação entre 5,00 e 104,99, variando a cada volta.
  centavos=$(( (volta * 7919) % 10000 + 500 ))
  valor="$((centavos / 100)).$((centavos % 100 / 10))$((centavos % 10))"
  codigos="$(requisicao POST "${DONATION_URL}/donations" \
    "{\"ngo_id\": ${NGO_ID}, \"amount\": ${valor}, \"donor_name\": \"Doador sintetico ${volta}\"}")"

  if [ $((volta % 5)) -eq 0 ]; then
    codigos="${codigos} $(requisicao GET "${DONATION_URL}/donations") $(requisicao GET "${NGO_URL}/ngos")"
  fi
  if [ $((volta % 10)) -eq 0 ]; then
    codigos="${codigos} $(requisicao POST "${VOLUNTEER_URL}/volunteers" \
      "{\"name\": \"Voluntario sintetico ${volta}\", \"email\": \"voluntario${volta}@example.org\", \"ngo_id\": ${NGO_ID}}")"
    codigos="${codigos} $(requisicao GET "${VOLUNTEER_URL}/volunteers/${NGO_ID}")"
  fi

  for codigo in $codigos; do
    case "$codigo" in
      2??) ok=$((ok + 1)) ;;
      *) falhas=$((falhas + 1)) ;;
    esac
  done

  # Uma linha de resumo por minuto (aproximado), em JSON, para o Loki.
  if [ $((volta % 60)) -eq 0 ]; then
    echo "{\"message\": \"traffic.summary\", \"service.name\": \"traffic-generator\", \"voltas\": ${volta}, \"respostas_2xx\": ${ok}, \"falhas\": ${falhas}}"
  fi
  sleep "$INTERVALO"
done
