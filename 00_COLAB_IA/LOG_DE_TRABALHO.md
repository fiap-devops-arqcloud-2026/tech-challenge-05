# Log de trabalho

TL;DR: C0 e C1 concluídas em 2026-11-20. Os três serviços compilam, têm testes, logs JSON e tracing, e rodam no Docker Compose com PostgreSQL e emulador da AWS; fluxo ponta a ponta e Trivy sem CRITICAL verificados localmente. Próximo: C2 (Terraform), que começa por leituras na conta e pede o perfil da AWS CLI (P-004).

Última atualização: 2026-11-20, Claude.

Formato: entrada nova no topo, sem apagar as anteriores. Cada entrada termina com "Estado p/ próximo agente". Horários em America/Sao_Paulo (UTC-03:00).

## 2026-11-20 21:50 — Claude — C1 concluída: serviços e contêineres

Feito:
- `donation-service`: `go.mod` corrigido (F-001) e `go.sum` gerado; `pgx` v5.13.0, `x/crypto` 0.59.0, OpenTelemetry 1.47.0 (D-016). `telemetry.go`: logs JSON com `trace_id`, tracing opt-in, desligamento gracioso. `sqs.go`: span PRODUCER com `traceparent` nas MessageAttributes (D-013). `main.go` com mudanças mínimas e `App.routes()`. 14 testes (go-sqlmock e SQS falsa).
- `ngo-service` e `volunteer-service`: dependências atualizadas (F-002, D-016); `telemetry.py` (logs JSON e spans de Flask, psycopg2 e botocore); `RealDictCursor` no pool. 17 e 8 testes (pool falso e Moto).
- Dockerfiles multi-stage com UID 10001, `.dockerignore` em lista de permissão, `pip` removido do runtime Python e atualizações de segurança do sistema aplicadas no build.
- `docker-compose.yaml` (PostgreSQL 17 com os dois bancos e os schemas do coordenador, Moto com fila e tabela, três serviços com healthcheck), `docker-compose.otel.yaml` (Collector local), `compose/`, `.env.example`, `scripts/integration/test_fluxo.py` e `scripts/test-compose.sh`.
- READMEs dos três serviços; README principal com a execução local; AGENTS.md com os comandos.
Verificação (local, 2026-11-20):
- `go vet` e `go test`: 14/14. O `-race` exige cgo e não roda neste Windows; fica para o CI Linux.
- `pytest` em `python:3.13-slim`: ngo 17/17, volunteer 8/8.
- `scripts/test-compose.sh`: 13/13 verificações. Com `WITH_OTEL=1`: 14/14 (inclui o `traceparent` na mensagem), spans dos três serviços no Collector e `/health` fora dos traces.
- Spans vistos no Collector: ngo (SERVER `GET/POST /ngos`, CLIENT `INSERT`/`SELECT`) e donation (SERVER `GET/POST /donations`, CLIENT `INSERT`/`SELECT donations`, PRODUCER `send solidary-donations`). Volunteer confirmado pelo `service.name`; os nomes dos spans dele não entraram na extração porque o lote ainda não tinha sido exportado. Daí a espera com tentativas no script.
- Trivy 0.76.2 (HIGH e CRITICAL, `ignore-unfixed=false`): **CRITICAL 0 nas três imagens**. Donation: HIGH 0. Ngo e volunteer: HIGH 47 cada, todos de 18 pacotes do Debian 13 sem correção publicada; nenhum HIGH com correção. Antes das correções havia: `pgproto3/v2` (HIGH sem correção no pgx v4), resolvido com o pgx v5; `msgpack` e `pkg_resources` embutidos no pip, resolvidos removendo o pip; e `zlib1g` com correção, resolvido pela atualização do sistema no build.
- Imagens com usuário 10001:10001; tamanhos 59 MB (donation), 226 MB (ngo) e 264 MB (volunteer).
- Diff dos serviços revisado contra `80a967f`: mudaram logs, telemetria, `RealDictCursor` no pool, desligamento e driver. SQL, validações, status e payloads ficaram iguais.
Achados: F-001 (`go.mod` inválido) e F-002 (Flask 2.2.2 incompatível com Werkzeug 3), registrados no DOSSIE.
Não feito: lint e SAST (gosec, golangci-lint, flake8, pylint, bandit) ficam para a C3; nenhuma operação AWS.
Estado p/ próximo agente: C2. Começar pelas leituras na conta listadas em PENDENCIAS; elas precisam do perfil da AWS CLI (P-004). Escrever as quatro raízes e validar offline (`fmt`, `validate`, `test`) antes de pedir qualquer apply. O Compose fica como referência dos nomes da fila (`solidary-donations`), da tabela e dos bancos.

## 2026-11-20 21:15 — Claude — C0 concluída: fundação do repositório e colaboração

Pedido: montar o projeto inteiro, só com os obrigatórios do mapa, com boas práticas de arquitetura cloud e DevOps, tudo comentado e documentado, mantendo o projeto atualizado para o Codex retomar a qualquer momento; trabalhar em camadas; não inventar dados e perguntar o que bloquear.
Feito:
- Respostas do usuário registradas em DECISOES (D-001 a D-015), com citação literal: conta da Fase 4 em modo liga/desliga; New Relic e Slack reaproveitados e PagerDuty em conta nova; DR pela Opção A (Velero); fluxo dev → PR → main como na Fase 4; README do coordenador movido para `docs/enunciado/`; Budget de US$ 50/mês. Escolhas técnicas do agente registradas para veto (D-009 a D-015).
- PR #1 (guias de estudo e mapa) já estava mesclado na `dev` pelo usuário (`4a6ef6b`); trabalho seguiu na `dev`.
- Commit `80a967f`: serviços e README do coordenador sem alterações (README movido byte a byte; SHA-256 `398fe05a…757e8756` antes e depois; HEAD do repositório oficial ainda `79f5c20`).
- Criados: `AGENTS.md`, `.claude/CLAUDE.md`, `00_COLAB_IA/` (LEIA-PRIMEIRO, PLANO_DE_ACAO com matriz dos 47 obrigatórios, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO), `02_TRABALHO/MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md` (gerado do workflow de leitura da Fase 4: 4 leitores + cruzamento), README do projeto, `docs/enunciado/README.md`, `.gitignore`, `.gitattributes`, `.editorconfig`, `SECURITY.md` e `scripts/security-check.sh`.
Verificação: `git check-ignore` confirma `.env`, `*.tfstate`, `*.tfplan`, `backend.hcl`, `*.tfvars`, kubeconfig e `*.pem` ignorados, e os `*.example` versionáveis; `security-check.sh` sem achados; mapeamento sem IDs de conta, e-mails ou nomes (varredura por regex).
Ambiente local: Go 1.27.1, Python 3.15.2, Terraform 1.16.0, kubectl 1.36.1, AWS CLI 2.35.11 e Docker Compose 5.6.1 instalados; Docker Desktop parado; sem Helm, Trivy, golangci-lint, Node e make.
Não feito: nenhuma operação AWS (nem leitura). Commit da C0 e push na `origin/dev` feitos logo depois desta entrada.
Estado p/ próximo agente: começar a C1 pela primeira caixa de PENDENCIAS. Ligar o Docker Desktop antes da validação (P-001). Dependências desatualizadas do código recebido (Flask 2.2.2, Go 1.21, aws-sdk-go v1) seguem a D-009: atualizar só o que o build ou o Trivy exigirem, registrando o motivo.

## 2026-11-20 15:53–20:35 — Claude — Leitura da Fase 4 e cruzamento com os obrigatórios

Feito: workflow de leitura do `tech-challenge-04` (somente leitura) com quatro leitores (IaC, CI/CD e GitOps, observabilidade e incidentes, serviços e colaboração) e um cruzamento com os 47 obrigatórios. Resultado: 11 camadas, 12 dúvidas consolidadas (DU-01 a DU-12) e 30 riscos, convertidos no mapeamento de `02_TRABALHO/` e no PLANO_DE_ACAO. As dúvidas viraram perguntas ao usuário ou decisões técnicas registradas (tabela de resolução no início do mapeamento).
Estado p/ próximo agente: não repetir a leitura; usar o mapeamento como referência e conferir no código da Fase 4 antes de copiar qualquer trecho.

## 2026-11-20 — Claude — Guias de estudo da Fase 5 e mapa de requisitos

Feito: cinco guias de estudo (um por pasta de aulas) e o mapa de requisitos (`docs/requisitos/`: 47 obrigatórios, 46 bônus, 19 sugestões e 22 dúvidas para o tutor). Commit `7552369`, PR #1 para a `dev`, mesclado pelo usuário (`4a6ef6b`).
Estado p/ próximo agente: material de estudo concluído; não faz parte das camadas de implementação.
