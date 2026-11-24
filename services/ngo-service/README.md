# ngo-service

Cadastro das ONGs parceiras da SolidaryTech. Python (Flask, servido pelo
Gunicorn); PostgreSQL `ngo_db`; porta 8081.

## Rotas

| Método | Rota | Resposta |
|---|---|---|
| GET | `/health` | 200 `{"status":"ok","service":"ngo-service"}` |
| POST | `/ngos` | 201 com a ONG criada; 400 campo ausente; 409 e-mail já cadastrado; 500 erro interno |
| GET | `/ngos` | 200 com a lista, da mais recente para a mais antiga |

Corpo do POST: `{"name": "...", "email": "...", "cause": "...", "city": "..."}` (os quatro obrigatórios).
O schema e o seed (duas ONGs) estão em `db/init.sql`.

## Variáveis de ambiente

| Variável | Obrigatória | Para que serve |
|---|---|---|
| `PORT` | não (8081) | Porta do Gunicorn (lida por ele em `0.0.0.0:$PORT`) |
| `DATABASE_URL` | sim | `postgresql://<usuario>:<senha>@<host>:5432/ngo_db` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | não | Liga o tracing (ex.: `http://otel-collector:4318`) |
| `OTEL_SERVICE_NAME` | não | Nome no APM (padrão `ngo-service`) |
| `OTEL_SDK_DISABLED` | não | `true` desliga o tracing mesmo com endpoint |
| `LOG_LEVEL` | não (INFO) | Nível dos logs |

## Testes e imagem

```bash
# Instala as dependências de teste (de preferência num ambiente virtual)
pip install -r requirements-dev.txt
```

```bash
# Testes: o PostgreSQL é substituído por um pool falso, sem rede
python -m pytest
```

```bash
# Imagem multi-stage: wheels no estágio 1, python:3.13-slim no runtime, usuário 10001
docker build -t solidarytech/ngo-service:local .
```

## O que mudou em relação ao código recebido

Rotas, payloads, regras de negócio e variáveis originais foram mantidos.

- **Dependências atualizadas** (versões em `requirements.txt`, conferidas em
  2026-11-20). O `Flask==2.2.2` recebido não importa com o Werkzeug 3, que o
  pip instala quando não há trava (`ImportError: cannot import name
  'url_quote'`); as versões antigas também têm vulnerabilidades conhecidas.
- **Logs JSON** com `trace_id` e um registro `http.request.completed` por
  requisição (fora `/health`), com a rota-modelo, o método e o status. Erros
  registram só o tipo da exceção.
- **Tracing OpenTelemetry** (`telemetry.py`, opt-in): spans do Flask e do
  psycopg2, sem parâmetros SQL.
- **`RealDictCursor` no pool**, e não em cada `conn.cursor(...)`: a
  instrumentação do psycopg2 troca a fábrica de cursores da conexão, e
  sobrescrevê-la no cursor descartaria o span da query. O resultado das
  rotas é o mesmo.

## Comportamentos herdados, mantidos de propósito

- O pool de conexões é criado no import e o processo encerra (código 1) se o
  banco não responder: no Kubernetes, o Pod reinicia até o banco estar pronto.
- Com o Werkzeug 3, um POST sem `Content-Type: application/json` recebe 415
  (Unsupported Media Type); payload JSON incompleto recebe 400.
