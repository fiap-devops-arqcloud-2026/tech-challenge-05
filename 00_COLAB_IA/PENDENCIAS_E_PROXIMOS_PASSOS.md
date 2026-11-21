# Pendências e próximos passos

TL;DR: C0 (fundação e colaboração) concluída em 2026-11-20. Próximo passo: C1 — serviços e contêineres (Dockerfiles, testes, OpenTelemetry e Docker Compose), toda local e sem custo. Nenhum recurso AWS existe nem foi criado na Fase 5.

Última atualização: 2026-11-20, Claude.

## Como usar

Retomar pela primeira caixa vazia da camada em andamento. Cada camada tem entregas e critério de pronto no [PLANO_DE_ACAO](PLANO_DE_ACAO.md). Ao concluir uma entrega: marcar aqui, registrar no [LOG](LOG_DE_TRABALHO.md) e atualizar a matriz do plano. Itens que dependem do usuário ficam na seção "Aguardando o usuário", com ID P-###.

## Camada em andamento — C1 Serviços e contêineres

- [ ] `donation-service`: `go.sum`, diretiva `go` e dependências mínimas; `telemetry.go`; logs JSON; desligamento gracioso; span PRODUCER com `traceparent` na SQS; testes.
- [ ] `ngo-service`: `telemetry.py`; logs JSON; testes; dependências fixadas.
- [ ] `volunteer-service`: `telemetry.py`; logs JSON; testes com Moto; dependências fixadas.
- [ ] Dockerfile e `.dockerignore` dos três serviços (multi-stage, não root).
- [ ] `docker-compose.yaml` (PostgreSQL com os dois bancos, Moto, três serviços, healthchecks) e `.env.example`.
- [ ] Teste de integração do Compose e verificação de spans no Collector local.
- [ ] Trivy nas três imagens sem CRITICAL; `services/<svc>/README.md`.
- [ ] LOG, PENDENCIAS e matriz atualizados; commit curado na `dev`.

Pré-requisito local: Docker Desktop em execução (estava parado em 2026-11-20 21:00). Go 1.27.1, Python 3.15.2, Terraform 1.16.0, kubectl 1.36.1 e AWS CLI 2.35.11 instalados; Helm, Kustomize standalone, Trivy, golangci-lint e Node não instalados (usar contêiner ou `kubectl kustomize`).

## Camadas seguintes

- [ ] C2 — Terraform (bootstrap, base, cluster, k8s), validado offline antes de qualquer apply.
- [ ] C3 — CI/CD DevSecOps.
- [ ] C4 — GitOps (ArgoCD), com Job de schema e gerador de tráfego.
- [ ] C5 — Observabilidade e APM.
- [ ] C6 — SRE.
- [ ] C7 — FinOps.
- [ ] C8 — ITSM e AIOps.
- [ ] C9 — DR e PCN (Opção A — Velero).
- [ ] C10 — Entregáveis.

## Aguardando o usuário

| ID | O que falta | Quem | Bloqueia |
|---|---|---|---|
| P-001 | Docker Desktop em execução para validar a C1 (o agente pode iniciá-lo; se não subir, o usuário confere). | Agente/usuário | C1 (validação) |
| P-002 | Criar a conta nova do PagerDuty (trial) perto da gravação e guardar a Integration Key no `.env` local. Campos marcados `A PREENCHER (PagerDuty)`. | Usuário | C8 |
| P-003 | Prazo, hora e canal de entrega (Q-06, Q-07); nomes, RMs e usernames dos integrantes; onde o vídeo será hospedado. | Usuário | C10 (o prazo também orienta o calendário) |
| P-004 | Perfil da AWS CLI a usar e autorização específica para cada apply/destroy, com o plano salvo apresentado antes. | Usuário | C2 em diante |
| P-005 | Conferir se o plano do New Relic tem detecção de anomalias (Applied Intelligence). | Agente com o usuário | C8 |
| P-006 | Aprovar metas SRE: SLOs, janela e termos do SLA, propostos pelo agente depois de medir. | Usuário | C6 |
| P-007 | Aprovar RTO e RPO-alvo das doações, propostos pelo agente depois do ensaio de restore. | Usuário | C9 |
| P-008 | Escolher o mecanismo de falha controlada da demonstração e o escopo do self-healing (proposta no C5). | Usuário | C8 |
| P-009 | Levar ao tutor as dúvidas do mapa que afetam a avaliação: Q-09 (automações da Fase 4), Q-13 (restore real?), Q-21 (Warm Standby), Q-22 (ElastiCache e Budgets). | Usuário | — |

## Concluído

### C0 — Fundação e colaboração (2026-11-20, Claude)

- [x] Decisões D-001 a D-015 registradas, com as respostas do usuário citadas.
- [x] README do coordenador copiado byte a byte para `docs/enunciado/` (SHA-256 igual); README do projeto na raiz.
- [x] `AGENTS.md`, `.claude/CLAUDE.md` e `00_COLAB_IA/` (LEIA-PRIMEIRO, PLANO_DE_ACAO, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO, mapeamento da Fase 4).
- [x] `.gitignore`, `.gitattributes`, `.editorconfig`, `SECURITY.md` e `scripts/security-check.sh`.
- [x] Código do coordenador versionado sem alteração, em commit próprio.

### Antes da C0 (2026-11-20, Claude)

- [x] Guias de estudo da Fase 5 e mapa de requisitos (PR #1, mesclado na `dev` pelo usuário em `4a6ef6b`).
