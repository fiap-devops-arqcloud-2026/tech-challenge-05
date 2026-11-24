# volunteer-service

Cadastro de voluntários das ONGs da SolidaryTech. Python (Flask, servido
pelo Gunicorn); DynamoDB `SolidaryTechVolunteers` (chave `volunteer_id`,
String); porta 8083.

## Rotas

| Método | Rota | Resposta |
|---|---|---|
| GET | `/health` | 200 `{"status":"ok","service":"volunteer-service"}` |
| POST | `/volunteers` | 201 com o voluntário (`volunteer_id` gerado); 400 campo ausente; 500 erro no DynamoDB |
| GET | `/volunteers/<ngo_id>` | 200 com os voluntários da ONG |

Corpo do POST: `{"name": "...", "email": "...", "ngo_id": 1}` (os três obrigatórios).

## Variáveis de ambiente

| Variável | Obrigatória | Para que serve |
|---|---|---|
| `PORT` | não (8083) | Porta do Gunicorn |
| `AWS_REGION` | não (us-east-1, padrão herdado) | Região da tabela; o projeto usa us-east-2 |
| `AWS_DYNAMODB_TABLE` | sim | Nome da tabela |
| `AWS_ENDPOINT_URL` | não | Só para teste local com emulador (Moto); vazio na AWS |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | não | Liga o tracing (ex.: `http://otel-collector:4318`) |
| `OTEL_SERVICE_NAME` | não | Nome no APM (padrão `volunteer-service`) |
| `OTEL_SDK_DISABLED` | não | `true` desliga o tracing mesmo com endpoint |
| `LOG_LEVEL` | não (INFO) | Nível dos logs |

Na AWS, a credencial do DynamoDB vem por IRSA (ServiceAccount do Pod), sem chave.

## Testes e imagem

```bash
# Instala as dependências de teste (de preferência num ambiente virtual)
pip install -r requirements-dev.txt
```

```bash
# Testes: o DynamoDB é simulado em memória pelo Moto, sem tocar a AWS
python -m pytest
```

```bash
# Imagem multi-stage: wheels no estágio 1, python:3.13-slim no runtime, usuário 10001
docker build -t solidarytech/volunteer-service:local .
```

## O que mudou em relação ao código recebido

Rotas, payloads, regras de negócio e variáveis originais foram mantidos.

- **Dependências atualizadas** (versões em `requirements.txt`, conferidas em
  2026-11-20). O `Flask==2.2.2` recebido não importa com o Werkzeug 3, que o
  pip instala quando não há trava; o boto3 atual também lê
  `AWS_ENDPOINT_URL`, o que permite o teste local sem mudar o código.
- **Logs JSON** com `trace_id` e um registro por requisição (fora `/health`).
  Erros registram só o tipo da exceção.
- **Tracing OpenTelemetry** (`telemetry.py`, opt-in): spans do Flask e do
  botocore (as chamadas `PutItem` e `Scan` ao DynamoDB viram spans CLIENT).

## Comportamentos herdados, mantidos de propósito

- A listagem usa `Scan` com filtro por `ngo_id`, como no original (o próprio
  código cita que, em produção, seria um índice secundário global).
- O DynamoDB devolve números como `Decimal`, que o Flask serializa como
  texto: no GET, `ngo_id` vem como `"1"`; no POST, como `1`.
- `ngo_id` não numérico no POST gera erro 500 (a conversão `int()` não é tratada).
