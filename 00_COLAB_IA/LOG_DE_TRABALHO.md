# Log de trabalho

TL;DR: C0 e C1 concluídas em 2026-11-20. C2 em andamento em 2026-11-21: Terraform das quatro raízes escrito e validado offline, revisão adversarial em curso, nada aplicado na AWS.

Última atualização: 2026-11-21, Claude.

Formato: entrada nova no topo, sem apagar as anteriores. Cada entrada termina com "Estado p/ próximo agente". Horários em America/Sao_Paulo (UTC-03:00).

## 2026-11-23 13:40 — Claude — Revisão da C2 concluída e correções aplicadas

Feito:
- Workflow `wf_c7818595-765` concluído: 3 revisores (resultado em cache) e o verificador. 18 achados: 1 ALTA, 3 MÉDIAS e 14 BAIXAS. 15 foram CONFIRMADOS e corrigidos em 31 arquivos de `terraform/`, quase todos de documentação e testes. 1 ficou INCERTO: a retenção de backup do RDS no plano FREE, que a documentação oficial não esclarece; fica 7 dias e o README do `cluster` documenta a troca para 1.
- Decisões do orquestrador aplicadas (D-017): bucket `-an` com `prevent_destroy` (o destroy final usa um `state_bucket_override.tf` local, ignorado pelo Git); `PullOnly` nos nós; `state_bucket` validado pelo sufixo `-<conta>-<região>-an`.
- Addons do EKS 1.37 conferidos por leitura em us-east-2: os 5 existem (`metrics-server` v0.9.1-eksbuild.2).
- README principal atualizado: estado das camadas e árvore com `terraform/` e `gitops/`. Contrato da C2 com uma segunda retificação.
Verificação: relatório do verificador com `fmt -check` limpo, `validate` verde nas 10 pastas, 88 cenários de `terraform test` e 0 falhas, e `security-check` limpo. Reexecução independente da suíte pelo orquestrador registrada no commit.
Pendências que a revisão deixou para as camadas seguintes:
- C3: checagem estática de `default_tags` nos 4 `providers.tf` e de `node_tags` no cluster; `id-token: write` só nos jobs que assumem role, e sem `environment:` neles (mudaria o subject do OIDC).
- C5/C6: StatefulSets com `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete`.
- C8: o RBAC do self-healing não pode ler Secrets (o `db-schema` tem a senha mestre), criar Pods ou Jobs, nem fazer patch livre em Deployments.
- Primeiro apply: o Budget usa campos obsoletos na API (`CostFilters`/`CostTypes`), e não se sabe se a API aceita filtrar por tag ainda não ativada.
- Leitura estrita do REQ-OBR-03: o provedor OIDC nasceu no console na Fase 4 e é adotado por import; recriá-lo pelo código seria decisão do usuário.
Estado p/ próximo agente: commitar as correções da revisão (só `terraform/` e os documentos), aguardar a finalização da C3 (`wf_a1547d2f-535`) e seguir o plano: validações gerais, commit da C3, CI no GitHub e autorização do primeiro plano na AWS.

## 2026-11-23 13:00 — Claude — Retomada depois do limite de uso

Feito:
- C4 commitada e enviada (`61ba960`).
- Revisão da C2 (`wf_c7818595-765`): os três revisores terminaram e o resultado ficou em cache no journal; o verificador parou no limite de uso. Ele foi retomado com `resumeFromRunId` às 12:55, e só ele roda.
- C3 (`wf_476ffd4c-f67`): os três agentes pararam no limite de uso, mas deixaram em disco `_ci-go.yml`, `_ci-python.yml`, os três chamadores, `terraform-check.yml`, `compose-integration.yml`, `repo-check.yml`, `set-repo-variables.sh`, `docs/CI-CD.md`, `.trivyignore` e as configurações de lint. As notas em `scratchpad/c3/` registram SHAs, versões, digests e decisões.
- Novo workflow `finalizar-c3-cicd` (`wf_a1547d2f-535`), com 2 agentes em paralelo e donos de arquivos separados: (1) completar e conferir os workflows, criar `gitops-check.yml`, acrescentar o job do robô que grava a tag no overlay e alinhar `docs/CI-CD.md`; (2) rodar localmente cada gate exatamente como os workflows definem e corrigir os achados nos serviços. Achados já conhecidos: errcheck em `donation-service/main.go` (`defer rows.Close()`), W391 no fim de `ngo-service/app.py` e pylint sem as dependências instaladas.
Estado p/ próximo agente: aguardar os dois workflows. Depois, conferir o resultado deles e rodar de novo as validações: Terraform offline (10 pastas), `scripts/gitops/validate.sh`, `scripts/test-compose.sh`, testes dos serviços, actionlint e `security-check.sh`. Em seguida, commitar a C2 revisada e a C3, conferir a primeira execução do CI no GitHub e pedir ao usuário a autorização do primeiro plano na AWS (P-004). Se um workflow cair de novo, retomar com `resumeFromRunId`: o que terminou fica em cache.

## 2026-11-22 22:00 — Claude — Retomada: C2 revisão e C3 relançadas; C4 validada

Pedido: o usuário pediu para retomar o trabalho.
Feito:
- Revisão da C2 (`wf_c7818595-765`) e C3 (`wf_476ffd4c-f67`) relançadas às 21:54. Os agentes leem o progresso salvo em `scratchpad/revisao-c2/` e `scratchpad/c3/`, que sobreviveu à parada.
- C4: `scripts/gitops/validate.sh` e `gitops/.kube-linter.yaml` escritos. Duas correções vieram do kube-linter: `unhealthyPodEvictionPolicy: AlwaysAllow` no PDB e `ttlSecondsAfterFinished` no Job. Também o `gitops/README.md`, com a divisão de donos entre GitOps e Terraform.
- Varredura de segredos: o ID da conta só é aceito no formato `<conta>.dkr.ecr.` dentro de `gitops/`. Testado com amostras falsas: o overlay passa; o mesmo endereço fora de `gitops/` e um ID solto dentro dele reprovam.
Verificação (local, 2026-11-22):
- `bash scripts/gitops/validate.sh`: cópias de SQL idênticas; 11 objetos renderizados pelo Kustomize 5.8.3; nenhum objeto do Terraform no GitOps; kubeconform estrito 11/11 válidos (schemas 1.34.12); kube-linter sem achados; shellcheck sem achados.
- `apply.sh` contra `postgres:17.12-alpine3.24`, com mestre não superusuário (`CREATEROLE CREATEDB`, como no RDS). 1ª execução: usuários, bancos, tabelas e seed (2 ONGs). 2ª execução: idempotente e com a senha do `ngo_app` trocada; a conexão pela rede já usou a senha nova. `ngo_app` recusado no `donation_db` ("does not have CONNECT privilege"); tabelas com dono `ngo_app`. A conferência da senha antiga por `127.0.0.1` não vale, porque a imagem oficial dá trust para conexões locais.
Não feito: workflow `gitops-check` e o job do CI que grava a tag no overlay (esperam a C3, para não disputar `.github/workflows/`); teste do gerador de tráfego no Compose (a C3 usa o Compose e as mesmas portas agora).
Estado p/ próximo agente: aguardar os dois workflows. Depois, integrar os resultados: correções da revisão da C2, a C3, o `gitops-check` e o job de tag; rodar de novo as validações (Terraform offline, `validate.sh`, `test-compose.sh` e os gates da C3); commitar e pedir ao usuário a autorização do primeiro plano na AWS (P-004).

## 2026-11-22 17:00 — Claude — Parada por limite de uso: C2 no GitHub, C3 e C4 em andamento

Feito:
- Commit `5c9d9c0` (C2 validada offline) enviado: `origin/dev = 5c9d9c0`.
- Revisão da C2 e C3 relançadas às 16:32 e PARADAS às ~17:00 pelo orquestrador (limite de uso da conta). O progresso dos revisores e dos agentes da C3 ficou em `scratchpad/revisao-c2/*.md` e `scratchpad/c3/*.md`, fora do repositório, e pode ter sido apagado se o scratchpad for limpo. O verificador da C2 não chegou a rodar: `terraform/` continua igual ao commit `5c9d9c0`.
- C4 iniciada à mão, NÃO commitada e AINDA NÃO validada: `gitops/base/` (Deployments, Services e PDB dos 3 serviços, Job `db-schema` como hook PreSync com `apply.sh` e cópias de `services/*/db/init.sql` em `sql/`, gerador de tráfego com `curlimages/curl:8.23.0`) e `gitops/overlays/prod/` (tags marcadoras até a primeira publicação).
- Decisão da C4, testada: o ID da conta fica no overlay (registro do ECR), gravado só pelo robô do CI. Um override só de nome no `kustomize edit set image` APAGA a tag (testado com o kustomize 5.8.3, o mesmo do ArgoCD 3.6.2), então não dá para tirar o registro do Git.
- Conferidos: UID/GID 100/101 do curl e 70/70 do postgres; imagens `ghcr.io/yannh/kubeconform:v0.8.0`, `stackrox/kube-linter:v0.8.3` e `koalaman/shellcheck:v0.11.0` existem; os schemas do kubeconform só vão até o Kubernetes 1.34.12.
Arquivos fora do Git: parciais da C3 (`.github/workflows/terraform-check.yml`, `compose-integration.yml` e `repo-check.yml`, `scripts/github/set-repo-variables.sh`, `services/donation-service/.golangci.yml`) e toda a pasta `gitops/`.
Estado p/ próximo agente:
1. Relançar a revisão da C2 (script `revisar-c2-terraform`) e a C3 (script `implementar-c3-cicd`). Os dois leem os arquivos de progresso, se existirem.
2. C4: escrever `scripts/gitops/validate.sh` (cópias de SQL idênticas; nenhum Namespace, Secret, ServiceAccount, StorageClass nem ConfigMap `aws-endpoints` em `gitops/`; build com o kustomize 5.8.3; kubeconform `-strict` com schemas 1.34.12; kube-linter com exceção justificada para `non-existent-service-account`, porque as ServiceAccounts vêm do Terraform; shellcheck nos dois scripts). Acrescentar à varredura de segredos a exceção `<12 dígitos>.dkr.ecr.` só em `gitops/`. Depois disso, o workflow `gitops-check` e o job do CI que grava a tag no overlay.
3. Só então commitar a C3 e a C4 e pedir ao usuário a autorização do primeiro plano na AWS (P-004).

## 2026-11-22 16:40 — Claude — Workflows derrubados por falha de rede; C2 salva em commit

Feito:
- Os workflows de revisão da C2 e de implementação da C3 terminaram sem resultado: todos os 7 agentes falharam com `API Error: Can't reach the API server (ENOTFOUND)`, uma falha de DNS. Eles já tinham parado às ~07:03 de 2026-11-21 e sido reiniciados às 11:20. A rede foi conferida às 16:30 de 2026-11-22: GitHub, registro do Terraform e PyPI responderam.
- Nenhum arquivo de `terraform/` mudou depois da validação de 2026-11-21 06:44 (conferido por data de modificação): o verificador da revisão não chegou a corrigir nada.
- A C3 deixou arquivos parciais: `.github/workflows/terraform-check.yml`, `compose-integration.yml` e `repo-check.yml`, `scripts/github/set-repo-variables.sh` e `services/donation-service/.golangci.yml`. Eles ficaram FORA deste commit, como ponto de partida da nova tentativa; os workflows dos serviços (`_ci-go.yml`, `_ci-python.yml` e os chamadores) não chegaram a ser escritos.
- Commit local da C2 validada offline (91 arquivos de `terraform/`, docs da C2 e a varredura de segredos ampliada), para que nada se perca se a rede cair de novo e para que as correções da revisão apareçam num diff próprio.
Estado p/ próximo agente: relançar a revisão da C2 (três frentes e o verificador) e a C3 a partir dos parciais. Os workflows agora gravam o progresso em `scratchpad/revisao-c2/` e `scratchpad/c3/`, fora do repositório; se caírem de novo, esses arquivos guardam os achados já feitos. Depois: rodar de novo a validação offline, commitar as correções e a C3 e pedir ao usuário a autorização do primeiro plano na AWS (P-004).

## 2026-11-21 06:55 — Claude — C2 em andamento: Terraform escrito e validado offline

Pedido: o usuário respondeu "Sim, seguir" à pergunta de seguir para a C2 começando por leituras na conta AWS com o perfil `default`.
Feito:
- Leituras somente de leitura na conta (2026-11-20 ~22:10): [LEITURA_AWS_C2](02_TRABALHO/LEITURA_AWS_C2_2026-11-20_v01.md). Conta limpa; provedor OIDC do GitHub existente; EKS 1.37 padrão; cota de 16 vCPU; US$ 126,41 de crédito; PostgreSQL 17.11; tipos elegíveis ao plano FREE. Política `AmazonEC2ContainerRegistryPullOnly` conferida (2026-11-21).
- Versões atuais conferidas nos registros: aws 6.73.0, kubernetes 3.5.0, helm 3.3.0, random 3.9.1, módulo VPC 6.8.0, charts argo-cd 10.18.2 (v3.6.2) e argocd-apps 2.0.8. Subject OIDC imutável do repositório conferido na API do GitHub.
- Contrato entre as raízes: [DESENHO_C2_TERRAFORM](02_TRABALHO/DESENHO_C2_TERRAFORM_2026-11-20_v01.md) (D-017).
- Workflow de implementação (3 agentes em paralelo + 1 de integração, ~8,7 h): `terraform/bootstrap`, `base`, `cluster`, `k8s` e os módulos `ecr`, `messaging`, `iam-ci`, `eks`, `rds` e `irsa`, adaptados da Fase 4, com README por raiz e `terraform/README.md`.
- `scripts/security-check.sh` passou a varrer também arquivos novos ainda não adicionados (`git grep --untracked`, `ls-files --others --exclude-standard`) e IDs de conta de 12 dígitos (permitidos só 000000000000 e 123456789012, do Moto). Testado com amostras falsas num repositório descartável.
Verificação (offline, 2026-11-21): `fmt -check` limpo; `init -backend=false` e `validate` verdes nas 10 pastas; `terraform test` com 83 cenários e 0 falhas; nenhuma divergência de nome entre produtores e consumidores de remote state; varredura de segredos limpa nos 91 arquivos novos.
Decisões do orquestrador sobre o que os agentes deixaram em aberto (D-017): bucket de estado no namespace regional da conta (`-an`) com `prevent_destroy`; nós com `PullOnly`; DynamoDB mantém a chave gerenciada; retenção de backup do RDS de 7 dias a confirmar na documentação (a Fase 4 usou 1 dia nesta conta FREE).
Em andamento: workflow de revisão adversarial (segurança e IAM; correção na AWS; FinOps, requisitos e docs) e um verificador que refuta ou confirma cada achado, aplica as decisões acima e as correções confirmadas e reroda os testes. Ele só altera `terraform/`.
Não feito: nenhum `plan` ou `apply` com backend; nada adicionado ao Git nesta camada.
Estado p/ próximo agente: se a revisão já terminou, conferir o resultado dela (relatório do verificador) e rodar de novo `fmt -check`, `validate` e `test` nas 10 pastas antes do commit. Depois, commit curado da C2 (arquivo por arquivo, incluindo os 10 `.terraform.lock.hcl`, sem as pastas `.terraform/`) e push na `dev`. O primeiro `plan` real só com autorização do usuário (P-004), começando pelo bootstrap com o `backend_override.tf` local descrito em `terraform/bootstrap/README.md`.

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
