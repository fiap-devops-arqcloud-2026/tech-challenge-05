# Plano de ação — SolidaryTech (Hackathon Fase 5)

TL;DR: Onze camadas, da fundação (C0) aos entregáveis (C10), cobrindo só os 47 obrigatórios do [mapa de requisitos](../docs/requisitos/README.md) (D-001). Cada camada tem objetivo, entregas, critério de pronto e dependências. Primeiro tudo roda e é validado localmente; a AWS só liga em janelas curtas e autorizadas (D-003). Estado: C0 e C1 concluídas em 2026-11-20; próxima, C2 (Terraform).

Última atualização: 2026-11-20, Claude.

## Princípios

1. **Simples, bem feito e funcionando.** Só obrigatórios. Bônus e sugestões ficam no backlog do mapa, para depois (D-001).
2. **Regra de Ouro do enunciado (p. 2).** Nada de deploy manual com `kubectl`, nada de infraestrutura clicada no console, nada de voo cego.
3. **Tudo como código, comentado e documentado.** Cada arquivo explica o porquê. Cada camada atualiza o LOG e as PENDENCIAS, para que outro agente retome a qualquer momento.
4. **Evidência em cinco estados, que não se substituem:** código existe → verificação local → CI verde → funcionando na AWS → evidência de entrega (print, vídeo ou relatório).
5. **Ambiente AWS efêmero.** Sobe para ensaio e gravação e é destruído depois, sempre com plano salvo (D-003, D-008).
6. **Reaproveitar a Fase 4 onde ela já resolve.** O que reaproveitar e as pegadinhas estão no [mapeamento da Fase 4](02_TRABALHO/MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md). A Fase 4 é só leitura.

## Visão geral

| Camada | Tema | Obrigatórios (REQ-OBR-) | Depende de | Estado |
|---|---|---|---|---|
| C0 | Fundação do repositório e colaboração | 01, 28, 46, 47 | — | ✅ concluída (2026-11-20) |
| C1 | Serviços e contêineres | 04, 05, 08, 13 | C0 | ✅ concluída (2026-11-20) |
| C2 | Infraestrutura como Código (Terraform) | 03, 06, 07, 19, 29 | C0 | ⏳ próxima |
| C3 | CI/CD DevSecOps (GitHub Actions) | 02, 08, 09, 10, 31 | C1, C2 | pendente |
| C4 | GitOps e deploy (ArgoCD) | 02, 06, 11, 30 | C2, C3 | pendente |
| C5 | Observabilidade e APM | 04, 12, 13 | C1, C4 | pendente |
| C6 | SRE: SLIs, SLOs, Error Budget e MTTR | 15, 16, 17, 18 | C4, C5 | pendente |
| C7 | FinOps | 19, 20, 21, 22 | C2, C4, C5 | pendente |
| C8 | ITSM e AIOps | 14, 23, 24 | C5, C6 | pendente |
| C9 | Disaster Recovery e PCN | 25, 26, 27 | C2, C4 | pendente |
| C10 | Entregáveis: evidências, relatório e vídeo | 01, 18, 28, 32–45, 47 | todas | pendente |

### Ordem de execução e janelas na AWS

```text
Local (sem custo)          Janela 1 (AWS)              Janela 2 (AWS)         Janela 3 (AWS)
C0 → C1 → código de        bootstrap → base →          tráfego estável;       ensaio final
C2/C3/C4/C5 validado       imagens (CI) → cluster →    C6, C7, C8, C9         e gravação (C10)
offline (validate, test,   k8s/ArgoCD; prova C3–C5     com medições           → destroy
render do Kustomize)       → destroy                   → destroy
```

Cada janela começa com autorização específica do usuário (P-004) e termina com destroy por plano salvo. A referência de custo da Fase 4 é de cerca de US$ 0,41/h com tudo ligado; o Budget da Fase 5 é de US$ 50/mês (D-008).

## C0 — Fundação do repositório e colaboração

**Objetivo:** repositório pronto para trabalho seguro e retomável por qualquer agente.

**Entregas:**
- [x] `AGENTS.md` (porta de entrada do Codex) e `.claude/CLAUDE.md` (Claude), ambos ponteiros para `00_COLAB_IA` (D-010).
- [x] `00_COLAB_IA/`: LEIA-PRIMEIRO, este plano, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO e o mapeamento da Fase 4 em `02_TRABALHO/`.
- [x] README do projeto na raiz; README do coordenador copiado byte a byte para `docs/enunciado/` (D-007).
- [x] Higiene: `.gitignore`, `.gitattributes`, `.editorconfig`, `SECURITY.md` e `scripts/security-check.sh`.
- [x] Código do coordenador versionado sem alterações em um commit próprio, para que o diff da C1 mostre só o que mudamos.

**Pronto quando:** um agente lendo só AGENTS.md → LEIA-PRIMEIRO → PENDENCIAS → topo do LOG descreve o estado e o próximo passo; `git check-ignore` confirma `.env`, `*.tfstate`, `*.tfplan` e kubeconfig ignorados; `scripts/security-check.sh` sem achados.

## C1 — Serviços e contêineres

**Objetivo:** os três serviços compilam, têm testes, estão instrumentados e rodam em contêineres otimizados localmente, sem mudança de regra de negócio (D-009).

**Entregas:**
- `donation-service` (Go, hot path): `go.sum` versionado; diretiva `go` e dependências no mínimo exigido pelo build e pelo scan; `telemetry.go` adaptado da Fase 4 (OTLP/HTTP, opt-in por variável); logs JSON com `trace_id`; desligamento gracioso (SIGTERM); spans de PostgreSQL e span PRODUCER na SQS com `traceparent` nas MessageAttributes (D-013); testes de handler.
- `ngo-service` e `volunteer-service` (Flask): `telemetry.py` da Fase 4; logs JSON; testes `pytest` (mocks no ngo, Moto no volunteer); dependências fixadas.
- Dockerfile e `.dockerignore` por serviço: multi-stage, usuário não root, imagem mínima (Go estático; Python slim com wheels; `exec gunicorn`).
- `docker-compose.yaml`: PostgreSQL com `ngo_db` e `donation_db` (os `init.sql` do coordenador), Moto para SQS e DynamoDB, os três serviços com healthcheck; sobreposição opcional com OTel Collector local.
- Teste de integração do Compose e `.env.example` com valores fictícios.
- `services/<svc>/README.md` com variáveis, portas e como testar.

**Pronto quando:** `go test ./...` e `pytest` verdes; `docker compose up --build --wait` saudável; fluxo ONG → doação (mensagem na fila do Moto) → voluntário passa; `trivy image` sem CRITICAL; `docker inspect` mostra usuário não root; Collector local recebe spans dos três serviços sem `/health`.

**Status (2026-11-20):** ✅ concluída, em verificação local. 14 testes Go, 17 do ngo e 8 do volunteer verdes; fluxo do Compose com 13 verificações (14 com tracing, que confere também o `traceparent` na mensagem SQS) e spans dos três serviços no Collector, sem `/health`; Trivy sem CRITICAL nas três imagens; usuário 10001 nas três. Detalhes e números do scan no LOG. Ainda não passou por CI (C3) nem pela AWS (C2/C4).

**Base na Fase 4:** `services/auth-service/{Dockerfile,telemetry.go}`, `services/flag-service/{Dockerfile,telemetry.py,tests/}`, `services/evaluation-service/sqs.go`, `docker-compose*.yaml`, `scripts/test-compose.sh`.

## C2 — Infraestrutura como Código (Terraform)

**Objetivo:** tudo o que existe na AWS nasce do Terraform, com as três tags obrigatórias (REQ-OBR-19).

**Entregas:**
- `terraform/bootstrap/`: bucket de estado (versionado, SSE, bloqueio público, só TLS), import do provedor OIDC do GitHub existente (D-012) e o AWS Budget de US$ 50/mês filtrado pela tag `Project` (D-008).
- `terraform/base/`: VPC (módulo da comunidade, 2 AZs, 1 NAT, endpoints de gateway S3 e DynamoDB), 3 ECR, fila SQS Standard das doações com DLQ, tabela DynamoDB `SolidaryTechVolunteers` (PK `volunteer_id`, String) com PITR, roles OIDC do CI e do self-healing.
- `terraform/cluster/`: EKS 1.37 (versão padrão, suporte padrão até 2027-11-30); 2 nós `m7i-flex.large` (cota de 16 vCPU em 2026-11-20); addons (vpc-cni, coredns, kube-proxy, EBS CSI com IRSA, metrics-server); uma instância RDS PostgreSQL 17 para `ngo_db` e `donation_db`, com backup automático e PITR; IRSA do donation (SQS) e do volunteer (DynamoDB); access entry do self-healing.

Contrato detalhado entre as raízes: [DESENHO_C2_TERRAFORM](02_TRABALHO/DESENHO_C2_TERRAFORM_2026-11-20_v01.md). Decisão: D-017.
- `terraform/k8s/`: namespaces, Secrets, StorageClass gp3 padrão com tags, ArgoCD por Helm e Applications.
- `default_tags` `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core` (+ `ManagedBy=Terraform`) em todos os providers, inclusive o da região secundária (D-015); propagação para nós e volumes.
- `terraform test` da trust OIDC, `fmt` e `validate` em todas as raízes.

**Pronto quando:** `validate`/`test` verdes offline; plano salvo revisado; apply autorizado concluído; conferência de tags devolve lista vazia.

**Base na Fase 4:** `terraform/{backend.tf,providers.tf,main.tf}`, `terraform/modules/{ecr,eks,irsa,iam-ci,messaging,rds}`, `terraform/cluster/`, `terraform/k8s/`.

## C3 — CI/CD DevSecOps (GitHub Actions)

**Objetivo:** cada mudança passa por testes, lint, SAST, SCA e scan de imagem; só a `main` publica no ECR (OIDC) e grava a tag no GitOps, sem `kubectl`.

**Entregas:**
- Workflows reutilizáveis `_ci-go.yml` e `_ci-python.yml` e um chamador por serviço: build e testes, lint, SAST (gosec/bandit), SCA, build da imagem, Trivy (CRITICAL derruba), push no ECR e commit da nova tag no overlay.
- `terraform-check.yml`, `gitops-check.yml` (render do Kustomize, validação e varredura de segredos) e `compose-integration.yml`.
- Variables do repositório geradas a partir dos outputs do Terraform; nenhum segredo AWS no GitHub.
- `docs/CI-CD.md`.

**Pronto quando:** PR roda tudo verde; push na `main` publica a imagem e gera o commit do robô; prova negativa registrada (teste quebrado ou CVE CRITICAL derruba o job).

## C4 — GitOps e deploy (ArgoCD)

**Objetivo:** o cluster reflete só o Git.

**Entregas:**
- `gitops/base/<svc>/`: Deployment com requests/limits, probes em `/health` e `securityContext` não root; Service; ServiceAccount.
- `gitops/overlays/prod/`: imagens (reescritas pelo CI), endpoints e anotações IRSA.
- Job de schema idempotente com os `init.sql` (no lugar do `kubectl run psql` da Fase 4).
- Gerador de tráfego sintético como Deployment no Git (liga e desliga por réplicas).
- Application da SolidaryTech (prune, selfHeal, retry).

**Pronto quando:** Application Synced/Healthy; 3 Deployments Ready; `GET /ngos` devolve o seed; `POST /donations` devolve 201 e a fila recebe a mensagem; voluntários funcionam no DynamoDB.

## C5 — Observabilidade e APM

**Objetivo:** métricas, logs e traces dos três serviços no cluster e traces no New Relic, sem ponto cego (D-004).

**Entregas:** app-of-apps (kube-prometheus-stack, Loki, OTel Collector gateway e agent) com versões revisadas; Secrets da observabilidade pelo Terraform; dashboard de visão geral (RPS, 5xx e p95 por serviço, recursos, logs) e alerta de 5xx como código.

**Pronto quando:** Applications Synced/Healthy; Grafana com dados dos três serviços; Loki com logs JSON e `trace_id`; New Relic com as três entidades e um trace do donation-service com spans de PostgreSQL e SQS.

## C6 — SRE

**Objetivo:** confiabilidade do donation-service definida, medida e visível.

**Entregas:** `docs/SRE_SLI_SLO_SLA.md` (2 SLIs, 1 SLO por SLI, janela, política de error budget e SLA); recording rules; dashboard SRE exclusivo de SLO e error budget; procedimento de medição do MTTR com linha do tempo de incidente simulado.

**Decisão do usuário:** metas, janela e termos do SLA (P-006). O agente propõe com base em medições.

## C7 — FinOps

**Objetivo:** custo rastreável por tag, requests/limits justificados por métrica e Forecast mensal com recomendação.

**Entregas:** script de conformidade de tags e ativação das tags de alocação de custo; PR de rightsizing via GitOps com tabela antes/depois; `docs/FINOPS_FORECAST.md` com preço, fonte e data de cada componente; ao menos uma recomendação nativa com economia estimada.

## C8 — ITSM e AIOps

**Objetivo:** detectar (alerta e IA do APM), notificar e remediar automaticamente, com o ciclo de vida do incidente desenhado.

**Entregas:** alerting do Grafana como código (PagerDuty, Slack e `repository_dispatch`); self-healing por GitHub Actions com allowlist; detecção de anomalias do New Relic ativada para o donation-service (P-005); `docs/ITSM_CICLO_INCIDENTE.md`.

**Decisão do usuário:** mecanismo de falha da demonstração (P-008). PagerDuty em conta nova, campos marcados "A PREENCHER (PagerDuty)" até lá (P-002).

## C9 — Disaster Recovery e PCN (Opção A — Velero)

**Objetivo:** PCN executivo com RTO e RPO das doações e backup/DR implementado e demonstrável (D-005).

**Entregas:**
- Terraform: bucket de backup em us-east-1 (versionado, cifrado, sem acesso público, com tags) e IRSA do Velero; RDS com retenção de backup, PITR e cópia dos backups em us-east-1; DynamoDB com PITR.
- GitOps: Application do Velero (Helm) com BackupStorageLocation e Schedule.
- `docs/PCN.md` e runbook de restore; ensaio cronometrado (apagar o namespace e restaurar).

**Decisão do usuário:** RTO e RPO-alvo (P-007), propostos pelo agente a partir do ensaio.

## C10 — Entregáveis

**Objetivo:** mostrar tudo funcionando: matriz de evidências fechada, relatório PDF com as quatro seções e vídeo de até 20 minutos.

**Entregas:** `docs/evidencias/`, relatório PDF (nomes, RMs, usernames, links, seções SRE, FinOps, Segurança e DR, ITSM/AIOps), roteiro do vídeo (pitch e demonstrações) e a matriz abaixo preenchida.

**Decisão do usuário:** integrantes, prazo e canal de entrega (P-003).

## Matriz dos 47 obrigatórios

Evidência esperada segundo o mapa: ● exigido, ◐ parcial ou recomendado. A coluna "Status" é atualizada a cada camada concluída.

<!-- MATRIZ:INICIO -->
| REQ | Requisito | Página | Camada | 📁 Repo | 🎬 Vídeo | 📄 Relatório | Status |
|---|---|---|---|:-:|:-:|:-:|---|
| [REQ-OBR-01](../docs/requisitos/README.md#req-obr-01) | Regra de Ouro: aplicar as Fases 1–4 | p. 2 | C0, C10 | ● | ● | ● | pendente |
| [REQ-OBR-02](../docs/requisitos/README.md#req-obr-02) | Zero deploy manual via kubectl | p. 2 | C3, C4 | ● | ● |  | pendente |
| [REQ-OBR-03](../docs/requisitos/README.md#req-obr-03) | Zero infraestrutura “clicada” no console | p. 2 | C2 | ● | ● |  | pendente |
| [REQ-OBR-04](../docs/requisitos/README.md#req-obr-04) | Zero “voo cego”: monitoramento profundo | p. 2 | C1, C5 | ● | ● |  | parcial: logs JSON e traces locais (C1); stack no cluster na C5 |
| [REQ-OBR-05](../docs/requisitos/README.md#req-obr-05) | Dockerfiles otimizados para os 3 serviços | p. 3 | C1 | ● | ◐ |  | ✅ código + verificação local (C1): multi-stage, não root, Trivy sem CRITICAL |
| [REQ-OBR-06](../docs/requisitos/README.md#req-obr-06) | Kubernetes gerenciado (EKS, AKS ou GKE) | p. 3 | C2, C4 | ● | ● |  | pendente |
| [REQ-OBR-07](../docs/requisitos/README.md#req-obr-07) | Terraform provisiona todo o ambiente | p. 3 | C2 | ● | ● |  | pendente |
| [REQ-OBR-08](../docs/requisitos/README.md#req-obr-08) | CI/CD automatizado com testes | p. 3 | C1, C3 | ● | ● |  | parcial: testes prontos (C1); pipeline na C3 |
| [REQ-OBR-09](../docs/requisitos/README.md#req-obr-09) | Scans SAST/SCA no pipeline | p. 3 | C3 | ● | ● |  | pendente |
| [REQ-OBR-10](../docs/requisitos/README.md#req-obr-10) | Build da imagem no pipeline | p. 3 | C2, C3 | ● | ● |  | pendente |
| [REQ-OBR-11](../docs/requisitos/README.md#req-obr-11) | GitOps com ArgoCD ou FluxCD | p. 3 | C4 | ● | ● |  | pendente |
| [REQ-OBR-12](../docs/requisitos/README.md#req-obr-12) | Stack de observabilidade rodando | p. 4 | C5 | ● | ● |  | pendente |
| [REQ-OBR-13](../docs/requisitos/README.md#req-obr-13) | APM com Distributed Tracing | p. 4 | C1, C5 | ● | ● |  | parcial: instrumentação e spans locais (C1); envio ao APM na C5 |
| [REQ-OBR-14](../docs/requisitos/README.md#req-obr-14) | Automação de resposta a incidentes | p. 2, 4, 6 | C8 | ◐ | ● | ● | pendente |
| [REQ-OBR-15](../docs/requisitos/README.md#req-obr-15) | ≥ 2 SLIs do donation-service | p. 4 | C6 |  | ● | ● | pendente |
| [REQ-OBR-16](../docs/requisitos/README.md#req-obr-16) | Um SLO para cada SLI | p. 4 | C6 |  | ● | ● | pendente |
| [REQ-OBR-17](../docs/requisitos/README.md#req-obr-17) | Dashboard SRE: SLOs e Error Budget | p. 4 | C6 | ◐ | ● | ◐ | pendente |
| [REQ-OBR-18](../docs/requisitos/README.md#req-obr-18) | Relatório: como o MTTR é reduzido | p. 4 | C6, C10 |  | ◐ | ● | pendente |
| [REQ-OBR-19](../docs/requisitos/README.md#req-obr-19) | Política de tags no Terraform | p. 4 | C2, C7 | ● | ● | ● | pendente |
| [REQ-OBR-20](../docs/requisitos/README.md#req-obr-20) | Rightsizing de requests/limits | p. 4 | C4, C5, C7 | ● | ◐ | ◐ | pendente |
| [REQ-OBR-21](../docs/requisitos/README.md#req-obr-21) | Forecast de custos mensais | p. 4 | C7 |  | ● | ● | pendente |
| [REQ-OBR-22](../docs/requisitos/README.md#req-obr-22) | ≥ 1 recomendação de otimização nativa | p. 4 | C7 |  | ● | ● | pendente |
| [REQ-OBR-23](../docs/requisitos/README.md#req-obr-23) | IA do APM detectando anomalias | p. 5 | C8 |  | ◐ | ◐ | pendente |
| [REQ-OBR-24](../docs/requisitos/README.md#req-obr-24) | Ciclo de vida do incidente desenhado | p. 5 | C8 |  | ◐ | ● | pendente |
| [REQ-OBR-25](../docs/requisitos/README.md#req-obr-25) | Documento executivo de PCN | p. 5 | C9 |  | ● | ● | pendente |
| [REQ-OBR-26](../docs/requisitos/README.md#req-obr-26) | RTO e RPO dos dados de doação | p. 5 | C9 |  | ● | ● | pendente |
| [REQ-OBR-27](../docs/requisitos/README.md#req-obr-27) | Estratégia de DR implementada | p. 5 | C9 | ◐ | ● | ● | pendente |
| [REQ-OBR-28](../docs/requisitos/README.md#req-obr-28) | Regra de avaliação: mostrar funcionando | p. 6 | C0, C10 |  | ● | ● | pendente |
| [REQ-OBR-29](../docs/requisitos/README.md#req-obr-29) | Repositório: Terraform com tags FinOps | p. 6 | C2 | ● |  |  | pendente |
| [REQ-OBR-30](../docs/requisitos/README.md#req-obr-30) | Repositório: YAML com requests/limits | p. 6 | C4, C7 | ● |  |  | pendente |
| [REQ-OBR-31](../docs/requisitos/README.md#req-obr-31) | Repositório: pipelines com DevSecOps | p. 6 | C3 | ● |  |  | pendente |
| [REQ-OBR-32](../docs/requisitos/README.md#req-obr-32) | Vídeo de até 20 minutos | p. 6 | C10 |  | ● |  | pendente |
| [REQ-OBR-33](../docs/requisitos/README.md#req-obr-33) | Pitch executivo para a diretoria | p. 6 | C10 |  | ● |  | pendente |
| [REQ-OBR-34](../docs/requisitos/README.md#req-obr-34) | Demo: CI/CD rodando + deploy via ArgoCD | p. 6 | C3, C4, C10 |  | ● |  | pendente |
| [REQ-OBR-35](../docs/requisitos/README.md#req-obr-35) | Demo: Terraform rodando / recursos com tags | p. 6 | C2, C7, C10 |  | ● |  | pendente |
| [REQ-OBR-36](../docs/requisitos/README.md#req-obr-36) | Demo: traces no APM e alertas | p. 6 | C5, C8, C10 |  | ● |  | pendente |
| [REQ-OBR-37](../docs/requisitos/README.md#req-obr-37) | Demo: Dashboard SRE com SLOs calculados | p. 6 | C6, C10 |  | ● |  | pendente |
| [REQ-OBR-38](../docs/requisitos/README.md#req-obr-38) | Demo: Backup/DR em ação | p. 6 | C9, C10 |  | ● |  | pendente |
| [REQ-OBR-39](../docs/requisitos/README.md#req-obr-39) | Relatório em PDF | p. 7 | C10 |  |  | ● | pendente |
| [REQ-OBR-40](../docs/requisitos/README.md#req-obr-40) | Relatório: nomes, RMs e usernames | p. 7 | C10 |  |  | ● | pendente |
| [REQ-OBR-41](../docs/requisitos/README.md#req-obr-41) | Relatório: links do repositório e do vídeo | p. 7 | C10 |  |  | ● | pendente |
| [REQ-OBR-42](../docs/requisitos/README.md#req-obr-42) | Seção SRE: SLI, SLO e SLA formais | p. 7 | C6, C10 |  |  | ● | pendente |
| [REQ-OBR-43](../docs/requisitos/README.md#req-obr-43) | Seção FinOps: Forecast + evidência de tags | p. 7 | C7, C10 |  |  | ● | pendente |
| [REQ-OBR-44](../docs/requisitos/README.md#req-obr-44) | Seção Segurança e DR: PCN + estratégia | p. 7 | C9, C10 |  |  | ● | pendente |
| [REQ-OBR-45](../docs/requisitos/README.md#req-obr-45) | Seção ITSM/AIOps: ciclo de incidentes | p. 7 | C8, C10 |  |  | ● | pendente |
| [REQ-OBR-46](../docs/requisitos/README.md#req-obr-46) | Desenvolvimento em grupo | p. 2 | C0 |  |  |  | pendente |
| [REQ-OBR-47](../docs/requisitos/README.md#req-obr-47) | Entrega dentro do prazo | p. 2 | C0, C10 |  |  |  | pendente |
<!-- MATRIZ:FIM -->

## Riscos principais

| Risco | Mitigação |
|---|---|
| Créditos (~US$ 126) e custo do ambiente ligado | Ambiente efêmero, Budget de US$ 50/mês e destroy por plano salvo ao fim de cada janela. |
| Cota de 5 vCPU On-Demand | Nós de 2 vCPU, rightsizing desde a C4 e observabilidade enxuta. |
| Versão do EKS sair do suporte padrão | Escolher a versão no dia do apply, conferida na AWS. |
| Dependências antigas do código recebido (Flask 2.2.2, Go 1.21) | Atualizar o mínimo exigido pelo build e pelo Trivy, com registro (D-009). |
| Velero não protege o RDS | PITR e cópia dos backups em us-east-1; DynamoDB com PITR (D-005). |
| Retenção do Prometheus menor que a janela do SLO | Dashboard calcula no intervalo selecionado; janela formal documentada (C6). |
| IA do APM precisa de histórico de tráfego | Gerador de tráfego estável antes da gravação (C4/C8). |
| Trial do PagerDuty dura pouco | Conta nova criada perto da gravação (P-002). |
| Seed e falha da demo sem `kubectl` | Job de schema no GitOps; falha controlada por mecanismo aprovado (P-008). |
| ElastiCache citado no README do coordenador | Fora do escopo: nenhum serviço usa cache (D-014); confirmar com o tutor (Q-22). |
