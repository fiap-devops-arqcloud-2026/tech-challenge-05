# Pendências e próximos passos

TL;DR: C0, C1 e C3 concluídas (CI verde no GitHub); C4 com os manifestos validados; C2 validada e revisada. Primeiro recurso na AWS em 2026-11-24: o bootstrap (bucket de estado, Budget de US$ 50/mês, provedor OIDC adotado), com o estado já no S3. Próximo passo: o usuário autorizar o apply da base, com o NAT desligado (o plano salvo é gerado e apresentado antes).

Última atualização: 2026-11-24, Claude.

## Fase AWS — ordem combinada (cada apply só com autorização do usuário, P-004)

1. [x] Bootstrap aplicado em 2026-11-24 ("Pode fazer o bucket s3"): bucket `solidarytech-tfstate-<conta>-us-east-2-an` (versionado, AES256, os 4 bloqueios públicos, só TLS, `prevent_destroy`), Budget `solidarytech-mensal` (US$ 50, alertas ACTUAL a 50/80/100% e FORECASTED a 100%, para o e-mail informado pelo usuário) e provedor OIDC do GitHub importado (só as tags mudaram). Estado em `phase5/prod/bootstrap.tfstate`. Evidências locais em `02_TRABALHO/validacao-local-bootstrap-2026-11-24/`, ignorada pelo Git.
2. [ ] Base com `enable_nat_gateway = false`: VPC, endpoints de gateway, 3 ECR, fila com DLQ, tabela, roles do CI e do self-healing. Sem NAT, o custo fixo fica perto de zero. Plano salvo gerado em 2026-11-24 (`terraform/base/base.tfplan`, local): 36 a criar, 0 a mudar, 0 a destruir, sem NAT nem EIP. Aguarda a autorização do usuário.
3. [ ] Variables do repositório com `scripts/github/set-repo-variables.sh`, a partir das saídas da base. Grava configuração no GitHub; pede autorização.
4. [ ] PR `dev` → `main` e merge (pede autorização): os pipelines publicam as 3 imagens no ECR e o robô grava as tags no overlay.
5. [ ] Tags de alocação de custo: `activate_cost_allocation_tags = true` no bootstrap, quando as chaves aparecerem no faturamento (até 24 h depois dos primeiros recursos tagueados).
6. [ ] Janela do cluster, combinada com o usuário (referência de custo da Fase 4: cerca de US$ 0,41/h com tudo ligado): NAT ligado na base, `cluster` (EKS, RDS, IRSA), `k8s` com `enable_applications = true` (ArgoCD e a Application), Job de schema e fluxo pela rede do cluster. Destroy na ordem inversa ao fim da janela.

## Como usar

Retomar pela primeira caixa vazia da camada em andamento. Cada camada tem entregas e critério de pronto no [PLANO_DE_ACAO](PLANO_DE_ACAO.md). Ao concluir uma entrega: marcar aqui, registrar no [LOG](LOG_DE_TRABALHO.md) e atualizar a matriz do plano. Itens que dependem do usuário ficam na seção "Aguardando o usuário", com ID P-###.

## Camada em andamento — C2 Infraestrutura como Código (Terraform)

Ferramentas: Terraform 1.16.0 e AWS CLI 2.35.11 instalados; Helm e Kustomize standalone não (usar `kubectl kustomize` e o provider Helm do Terraform). Docker Desktop iniciado em 2026-11-20 (P-001 resolvida).

- [ ] C2 — Terraform (bootstrap, base, cluster, k8s), validado offline antes de qualquer apply:
  - [x] Leituras na conta, sem criar nada (2026-11-20, perfil `default`): [LEITURA_AWS_C2](02_TRABALHO/LEITURA_AWS_C2_2026-11-20_v01.md).
  - [x] Contrato entre as raízes: [DESENHO_C2_TERRAFORM](02_TRABALHO/DESENHO_C2_TERRAFORM_2026-11-20_v01.md) (D-017).
  - [x] `terraform/bootstrap/`: bucket de estado, import do provedor OIDC, Budget de US$ 50/mês e tags de alocação de custo (desligadas até a C7).
  - [x] `terraform/base/`: VPC, endpoints de gateway, 3 ECR, SQS com DLQ, DynamoDB com PITR, roles OIDC do CI e do self-healing.
  - [x] `terraform/cluster/`: EKS 1.37, node group com launch template, addons, RDS PostgreSQL 17, IRSA do donation e do volunteer, access entry do self-healing.
  - [x] `terraform/k8s/`: namespace, Secrets, ConfigMap, ServiceAccounts, StorageClass gp3, ArgoCD e Application (desligada até a C4).
  - [x] `default_tags` com as tags obrigatórias; `fmt`, `validate` e `terraform test` offline nas 10 pastas (83 cenários, 2026-11-21).
  - [x] Revisão adversarial (segurança, correção na AWS, FinOps e docs) concluída em 2026-11-23: 18 achados, 15 corrigidos, 1 incerto (retenção do RDS); 88 cenários de teste.
  - [x] Commit curado da C2 (`5c9d9c0`) e push na `dev`; correções da revisão num commit próprio.
  - [x] Addons do EKS 1.37 conferidos por leitura (os 5 existem em us-east-2).
  - [x] Bootstrap: plano salvo apresentado, autorizado e aplicado em 2026-11-24 (1 importado, 8 criados, 1 alterado, 0 destruído); estado migrado para o S3 e plano seguinte com "No changes".
  - [ ] Base, cluster e k8s: plano salvo de cada raiz apresentado ao usuário antes do apply (P-004). No cluster, conferir se o plano FREE aceita 7 dias de retenção de backup do RDS.

Herdado da implementação para as próximas camadas:
- C3: o workflow de verificação do Terraform roda `init -backend=false`, `validate` e `test` nas 10 pastas (4 raízes e 6 módulos), sem credencial AWS; o push da imagem pula quando a tag imutável já existe no ECR (a role do CI tem `ecr:DescribeImages` para isso); as Variables do repositório saem dos outputs da base (`aws_region`, `ecr_registry`, `ci_role_arn`, `self_healing_role_arn`, `eks_cluster_name`).
- C4: os manifestos não declaram o namespace, os Secrets, o ConfigMap, as ServiceAccounts nem a StorageClass, que a raiz `k8s` cria; o Job de schema cria `ngo_db`, `donation_db` e os usuários `ngo_app` e `donation_app` e roda `ALTER ROLE ... PASSWORD` a cada execução (as senhas vêm do Secret `db-schema`); `enable_applications = true` só depois de as imagens existirem no ECR.
- C8: o RBAC do self-healing usa exatamente o grupo `solidarytech-self-healing`, no namespace `solidarytech`, só para reiniciar os Deployments.
- C7: ativar as tags de alocação de custo (`activate_cost_allocation_tags = true`) cerca de 24 h depois dos primeiros recursos tagueados.

## Camadas seguintes

- [ ] C3 — CI/CD DevSecOps:
  - [x] 9 workflows: `_ci-go.yml` e `_ci-python.yml` (testes, lint, SAST, SCA, imagem com Trivy, publicação no ECR por OIDC só em push na `main` e o robô do GitOps), 3 chamadores, `terraform-check`, `compose-integration`, `repo-check` e `gitops-check`. Actions fixadas por SHA (43 `uses`, conferidos) e ferramentas por versão e digest.
  - [x] Ensaio local de cada gate nos 3 serviços, nas mesmas versões e digests do CI, todos verdes depois de três correções: errcheck no donation, W391 no ngo e pylint com as dependências instaladas (nota 9,47). actionlint sem achados. Compose 13/13 depois das correções.
  - [x] Robô do GitOps simulado num clone descartável: 132 conferências, 0 falhas (idempotência, três robôs concorrentes, conflito de rebase, revert, trava contra versão antiga e contra mudança fora da linha `image`).
  - [x] `docs/CI-CD.md` (o que roda em cada evento, gates, OIDC de 15 min, robô, como voltar uma versão, reprodução local) e `scripts/github/set-repo-variables.sh` (não executado).
  - [x] Commit da C3 (`721b9bb`) e primeira execução no GitHub (push na `dev`, 2026-11-23). Os 7 workflows passaram: Terraform 11 jobs, cada serviço 5 jobs (publicação e robô pulados, como esperado na `dev`), GitOps, Repositório (3 jobs) e Compose, somando 31 jobs verdes.
  - [ ] Prova de que as barreiras derrubam, numa branch descartável (roteiro em `docs/CI-CD.md`).
  - [ ] Depois do apply da base: `scripts/github/set-repo-variables.sh` (grava Variables no GitHub; pede autorização) e a primeira publicação no ECR num push na `main`.
  - Observações: o Trivy acha 8 CRITICAL no Alpine da imagem oficial do Kustomize 5.8.3 (o binário tem 0), usada só em ferramenta com `--network none`; trocar o digest quando sair imagem corrigida. O govulncheck aponta GO-2022-0646 e GO-2022-0635 no aws-sdk-go v1 (S3 Crypto, não chamado; sem correção na v1).
- [ ] C4 — GitOps (ArgoCD), adiantada em 2026-11-22 enquanto a C2 é revisada e a C3 escrita:
  - [x] `gitops/base/`: Deployments, Services e PDB dos 3 serviços (requests/limits, probes, não root, disco somente leitura), Job `db-schema` PreSync idempotente e gerador de tráfego; `gitops/overlays/prod/` com tags marcadoras.
  - [x] `scripts/gitops/validate.sh` verde: cópias de SQL, render com o Kustomize 5.8.3, dono único (nada do Terraform no GitOps), kubeconform estrito, kube-linter e shellcheck.
  - [x] `apply.sh` do Job testado contra PostgreSQL 17 real, duas vezes (idempotente, troca de senha, menor privilégio).
  - [x] Varredura de segredos aceita o ID da conta só no formato `<conta>.dkr.ecr.` em `gitops/` (o robô do CI grava o registro no overlay).
  - [x] Workflow `gitops-check.yml` rodando `scripts/gitops/validate.sh` (imagens das ferramentas fixadas por digest).
  - [x] Job do CI que grava `<registro>/solidarytech/<svc>:<sha>` no overlay com commit do robô na `main` (Kustomize 5.8.3, até 5 tentativas com rebase), simulado; roda de verdade só no primeiro push na `main` com as Variables gravadas.
  - [ ] Teste do gerador de tráfego no Compose (depois da C3, que também usa o Compose e as mesmas portas).
  - [ ] Na AWS (depois do apply autorizado da C2 e das imagens no ECR): `enable_applications = true`, Application Synced/Healthy, Job de schema concluído, fluxo pela rede do cluster.
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
| P-004 | Autorização específica para cada apply/destroy, com o plano salvo apresentado antes. Perfil da AWS CLI: `default`, o único configurado. Bootstrap autorizado e aplicado em 2026-11-24; próxima: a base. | Usuário | C2 em diante |
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
