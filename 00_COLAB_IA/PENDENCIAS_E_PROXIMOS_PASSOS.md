# Pendências e próximos passos

TL;DR: C0 e C1 concluídas em 2026-11-20 (serviços conteinerizados, testados e instrumentados, verificados localmente). Próximo passo: C2 — Terraform, a começar pelas leituras na conta, que pedem o perfil da AWS CLI (P-004). Nenhum recurso AWS existe nem foi criado na Fase 5.

Última atualização: 2026-11-20, Claude.

## Como usar

Retomar pela primeira caixa vazia da camada em andamento. Cada camada tem entregas e critério de pronto no [PLANO_DE_ACAO](PLANO_DE_ACAO.md). Ao concluir uma entrega: marcar aqui, registrar no [LOG](LOG_DE_TRABALHO.md) e atualizar a matriz do plano. Itens que dependem do usuário ficam na seção "Aguardando o usuário", com ID P-###.

## Camada em andamento — C2 Infraestrutura como Código (Terraform)

Ferramentas: Terraform 1.16.0 e AWS CLI 2.35.11 instalados; Helm e Kustomize standalone não (usar `kubectl kustomize` e o provider Helm do Terraform). Docker Desktop iniciado em 2026-11-20 (P-001 resolvida).

- [ ] C2 — Terraform (bootstrap, base, cluster, k8s), validado offline antes de qualquer apply:
  - [ ] Leituras na conta (sem criar nada): identidade, provedor OIDC do GitHub existente, versões do EKS em suporte padrão, cota de vCPU em us-east-2 e us-east-1. Pede o perfil da AWS CLI (P-004).
  - [ ] `terraform/bootstrap/`: bucket de estado, import do provedor OIDC e Budget de US$ 50/mês (D-008, D-012).
  - [ ] `terraform/` (base): VPC, 3 ECR, SQS com DLQ, DynamoDB com PITR, roles OIDC do CI e do self-healing.
  - [ ] `terraform/cluster/`: EKS, node group, addons, RDS PostgreSQL 17 com `ngo_db` e `donation_db` (backup e PITR), IRSA do donation e do volunteer, access entry do self-healing.
  - [ ] `terraform/k8s/`: namespaces, Secrets, StorageClass gp3, ArgoCD e Applications.
  - [ ] `default_tags` com as três tags obrigatórias; `terraform test` da trust OIDC; `fmt` e `validate` offline.
  - [ ] Plano salvo de cada raiz apresentado ao usuário antes de qualquer apply (P-004).

## Camadas seguintes

- [ ] C3 — CI/CD DevSecOps (inclui lint e SAST dos três serviços e `go test -race` no Linux).
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
| P-002 | Criar a conta nova do PagerDuty (trial) perto da gravação e guardar a Integration Key no `.env` local. Campos marcados `A PREENCHER (PagerDuty)`. | Usuário | C8 |
| P-003 | Prazo, hora e canal de entrega (Q-06, Q-07); nomes, RMs e usernames dos integrantes; onde o vídeo será hospedado. | Usuário | C10 (o prazo também orienta o calendário) |
| P-004 | Perfil da AWS CLI a usar e autorização específica para cada apply/destroy, com o plano salvo apresentado antes. | Usuário | C2 em diante |
| P-005 | Conferir se o plano do New Relic tem detecção de anomalias (Applied Intelligence). | Agente com o usuário | C8 |
| P-006 | Aprovar metas SRE: SLOs, janela e termos do SLA, propostos pelo agente depois de medir. | Usuário | C6 |
| P-007 | Aprovar RTO e RPO-alvo das doações, propostos pelo agente depois do ensaio de restore. | Usuário | C9 |
| P-008 | Escolher o mecanismo de falha controlada da demonstração e o escopo do self-healing (proposta no C5). | Usuário | C8 |
| P-009 | Levar ao tutor as dúvidas do mapa que afetam a avaliação: Q-09 (automações da Fase 4), Q-13 (restore real?), Q-21 (Warm Standby), Q-22 (ElastiCache e Budgets). | Usuário | — |

## Concluído

### C1 — Serviços e contêineres (2026-11-20, Claude)

- [x] `donation-service`: `go.mod` corrigido, `go.sum`, pgx v5, `telemetry.go`, `sqs.go` com `traceparent`, desligamento gracioso, 14 testes.
- [x] `ngo-service` e `volunteer-service`: dependências atualizadas, `telemetry.py`, 17 e 8 testes.
- [x] Dockerfiles multi-stage não root (UID 10001) e `.dockerignore`; Trivy sem CRITICAL nas três imagens.
- [x] `docker-compose.yaml`, `docker-compose.otel.yaml`, `compose/`, `.env.example`, teste de integração e `scripts/test-compose.sh` (13/13; 14/14 com tracing).
- [x] READMEs dos serviços, README principal e AGENTS.md; LOG, PENDENCIAS e matriz atualizados.
- [x] P-001 resolvida: Docker Desktop iniciado pelo agente.

### C0 — Fundação e colaboração (2026-11-20, Claude)

- [x] Decisões D-001 a D-015 registradas, com as respostas do usuário citadas.
- [x] README do coordenador copiado byte a byte para `docs/enunciado/` (SHA-256 igual); README do projeto na raiz.
- [x] `AGENTS.md`, `.claude/CLAUDE.md` e `00_COLAB_IA/` (LEIA-PRIMEIRO, PLANO_DE_ACAO, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO, mapeamento da Fase 4).
- [x] `.gitignore`, `.gitattributes`, `.editorconfig`, `SECURITY.md` e `scripts/security-check.sh`.
- [x] Código do coordenador versionado sem alteração, em commit próprio.

### Antes da C0 (2026-11-20, Claude)

- [x] Guias de estudo da Fase 5 e mapa de requisitos (PR #1, mesclado na `dev` pelo usuário em `4a6ef6b`).
