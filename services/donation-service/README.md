# donation-service

Processamento de doações da SolidaryTech: o **hot path** da plataforma.
Grava a doação no PostgreSQL (`donation_db`) com status `APPROVED`
(simulação de gateway de pagamento) e publica um evento na fila SQS.
Linguagem Go; porta 8082.

## Rotas

| Método | Rota | Resposta |
|---|---|---|
| GET | `/health` | 200 `{"status":"ok","service":"donation-service"}` |
| POST | `/donations` | 201 com a doação gravada; 400 payload inválido; 500 erro no banco |
| GET | `/donations` | 200 com a lista, da mais recente para a mais antiga |
| outros | `/donations` | 405 |

Exemplo de corpo do POST: `{"ngo_id": 1, "amount": 50.5, "donor_name": "Maria"}`.
O evento publicado na SQS é o JSON da doação gravada (com `id`, `status` e `created_at`).

## Variáveis de ambiente

| Variável | Obrigatória | Para que serve |
|---|---|---|
| `PORT` | não (8082) | Porta HTTP |
| `DATABASE_URL` | sim | `postgres://<usuario>:<senha>@<host>:5432/donation_db` |
| `AWS_REGION` | para a SQS | Região da fila |
| `AWS_SQS_URL` | para a SQS | URL da fila. Sem ela (ou sem a região), a publicação fica desligada, como no original |
| `AWS_ENDPOINT_URL` | não | Só para teste local com emulador (Moto); vazio na AWS |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | não | Liga o tracing (ex.: `http://otel-collector:4318`) |
| `OTEL_SERVICE_NAME` | não | Nome no APM (padrão `donation-service`) |
| `OTEL_SDK_DISABLED` | não | `true` desliga o tracing mesmo com endpoint |

Na AWS, a credencial da SQS vem por IRSA (ServiceAccount do Pod), sem chave.

## Testes e imagem

```bash
# Testes unitários: banco simulado (go-sqlmock) e SQS falsa, sem rede
go test ./...
```

```bash
# Imagem multi-stage: golang:1.27-alpine para compilar, alpine:3.24 para rodar, usuário 10001
docker build -t solidarytech/donation-service:local .
```

O ambiente local completo (PostgreSQL, emulador de SQS e os três serviços)
sobe pelo `docker-compose.yaml` da raiz; veja o README principal.

## O que mudou em relação ao código recebido

As rotas, os payloads, as regras de negócio e as variáveis originais foram
mantidos. Mudanças de engenharia de plataforma:

- **`go.mod` corrigido:** o arquivo recebido declarava
  `github.com/jackc/pgx/v4/stdlib v4.18.3` como módulo (é um pacote do
  `pgx/v4`), e o Go recusava o `go.mod` inteiro. A linha saiu e o `go.sum`
  foi gerado. A diretiva `go` subiu para 1.26, exigida pelas dependências.
- **Dependências:** driver PostgreSQL `pgx` v4.18.3 → v5.13.0 (o v4 traz o
  `pgproto3/v2`, com vulnerabilidade HIGH sem correção nessa linha; a troca
  é só o import `pgx/v5/stdlib`, com o mesmo nome de driver e a mesma URL de
  conexão); `golang.org/x/crypto` 0.20.0 → 0.59.0 e `golang.org/x/text`
  0.14.0 → 0.44.0 (versões antigas com vulnerabilidades conhecidas);
  OpenTelemetry 1.47.0 e `otelhttp` 0.72.0 adicionados.
- **Logs JSON** (`log/slog`) com `trace_id` e `span_id`. Erros registram só
  o tipo do erro, sem a mensagem do driver (que pode trazer host e usuário).
- **Tracing OpenTelemetry** (`telemetry.go`, opt-in): span SERVER por
  requisição (fora `/health`), span CLIENT em cada query e span PRODUCER na
  publicação, com o `traceparent` nas MessageAttributes da mensagem (`sqs.go`).
- **Publicação na SQS:** continua assíncrona, agora com prazo de 5 s e
  contada para o desligamento gracioso.
- **Desligamento gracioso:** no SIGTERM, para de aceitar conexões, termina as
  requisições em andamento e espera os eventos SQS antes de sair.
- **`AWS_ENDPOINT_URL`:** permite usar um emulador no teste local.
- As rotas são montadas em `App.routes()`, que os testes também usam.

## Comportamentos herdados, mantidos de propósito

- As respostas de erro usam `http.Error`: o corpo é JSON, mas o
  `Content-Type` é `text/plain`.
- `ngo_id` e `amount` não são validados (qualquer número é aceito).
- Falha ao publicar na SQS não muda a resposta: a doação já foi gravada, e a
  falha fica registrada no log e no span.
