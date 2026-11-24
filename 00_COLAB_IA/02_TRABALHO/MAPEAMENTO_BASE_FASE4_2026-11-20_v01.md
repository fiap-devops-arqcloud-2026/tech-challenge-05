# Mapeamento da base reaproveitável da Fase 4

TL;DR: Fotografia de 2026-11-20 do repositório `tech-challenge-04` (somente leitura), em quatro frentes, cruzada com os 47 obrigatórios da Fase 5. Diz o que reaproveitar, o que muda e onde estão as pegadinhas. Os números citados são da Fase 4 e não valem como medição da Fase 5.

Última atualização: 2026-11-20, Claude.

Caminhos relativos à raiz de `tech-challenge-04`. As dúvidas DU-xx foram respondidas ou encaminhadas no mesmo dia; o resultado está em [DECISOES](../DECISOES.md) e na tabela abaixo. O plano por camadas que usa este mapeamento está em [PLANO_DE_ACAO](../PLANO_DE_ACAO.md).

## Como as dúvidas foram resolvidas

| Dúvida | Tema | Resolução |
|---|---|---|
| DU-01 | Conta, teto e ciclo de vida | D-003 (conta da Fase 4, liga/desliga) e D-008 (Budget de US$ 50/mês). Perfil da AWS CLI e confirmação de apply: P-004. |
| DU-02 | Regiões | D-003: us-east-2 primária; us-east-1 secundária (DR). |
| DU-03 | Bootstrap e provedor OIDC | D-012: raiz terraform/bootstrap; provedor OIDC existente importado, sem recriar. |
| DU-04 | Repositório e fluxo | D-006: dev → PR → main, como na Fase 4; repositório público. |
| DU-05 | Mexer no código recebido | D-009: alterações mínimas e documentadas, sem mudar regra de negócio. |
| DU-06 | Trace entre serviços | D-013: serviços independentes, contexto W3C na mensagem SQS. |
| DU-07 | APM, incidentes e ChatOps | D-004: New Relic e Slack da Fase 4; PagerDuty em conta nova (P-002). |
| DU-08 | Metas SRE | Pendente (P-006, camada C6): proposta do agente, aprovação do usuário. |
| DU-09 | Estratégia de DR | D-005: Opção A (Velero). Metas de RTO/RPO: P-007, camada C9. |
| DU-10 | Falha da demonstração | Pendente (P-008, camadas C5/C8). |
| DU-11 | Integrantes e prazo | Pendente (P-003): prazo assim que houver; dados pessoais no C10. |
| DU-12 | Convenções de colaboração | D-010 e D-011: ponteiros AGENTS.md e .claude/CLAUDE.md, numeração nova, D-018 mantida; D-007: README do coordenador em docs/enunciado. |

## Sumário

1. [Infraestrutura como Código (Terraform)](#1-iac)
2. [CI/CD DevSecOps e GitOps](#2-cicd)
3. [Observabilidade e resposta a incidentes](#3-obs)
4. [Serviços, contêineres e colaboração](#4-svc)
5. [Cruzamento dos 47 obrigatórios](#cruzamento)
6. [Riscos consolidados](#riscos)

<a id="1-iac"></a>
## 1. Infraestrutura como Código (Terraform)

Na Fase 4, a IaC é Terraform dividido em três raízes independentes, cada uma com seu próprio estado. Todas usam o mesmo bucket S3 com backend parcial (encrypt=true, use_lockfile=true, sem DynamoDB) e as chaves phase4/prod/{base,cluster,k8s}.tfstate. Bucket e região ficam em um backend.hcl local que o Git ignora. A conta AWS é pessoal e nova, no plano FREE com créditos, e a região é us-east-2. Não é AWS Academy/LabRole: o projeto foi desenhado justamente para criar roles, policies e OIDC por código. A raiz base (terraform/) cria a VPC pelo módulo da comunidade (2 AZs, 1 NAT), 5 ECR, SQS com DLQ, DynamoDB e o IAM do GitHub Actions via OIDC: uma role de push no ECR e uma role de self-healing. A raiz terraform/cluster/ lê a base por terraform_remote_state e cria o EKS 1.34 com node group gerenciado (2 nós m7i-flex.large na prática), os addons gerenciados (vpc-cni, coredns, kube-proxy, EBS CSI com IRSA e metrics-server), 2 RDS PostgreSQL 16, 1 ElastiCache Redis, as roles IRSA dos pods e o access entry do self-healing. A raiz terraform/k8s/ autentica os providers kubernetes/helm por 'aws eks get-token'. Ela cria namespaces, Secrets, a StorageClass gp3 padrão, o ArgoCD via Helm e as Applications da aplicação e da observabilidade. A ordem é: base, publicação das imagens pelo CI, cluster, preenchimento manual do overlay GitOps com os outputs e, por fim, k8s em duas etapas (primeiro -target=helm_release.argocd, depois o apply completo). Os segredos nascem de random_password (as senhas dos RDS também vão para o Secrets Manager) ou entram por TF_VAR_* sensíveis carregadas de um .env local. Eles chegam ao cluster como kubernetes_secret_v1 criados pela camada k8s, já que o ESO foi descartado. Pods acessam a AWS por IRSA e o CI por OIDC, sem chaves estáticas. Todas as raízes usam allowed_account_ids e default_tags (project=fiap, phase=4). A prática de custo foi destruir e recriar com planos salvos: force_delete, sem snapshot final, sem deletion protection, recovery_window 0 e reclaim Delete. Em 2026-11-12 tudo foi destruído, inclusive o bucket. O consumo de 09 a 12/11 foi de US$ 33,55, coberto por créditos. Ficaram fora do Terraform: o bucket de estado, o provedor OIDC do GitHub, o AWS Budget, as Variables do GitHub, o preenchimento do overlay, o seed de bancos e da chave de serviço e as conferências do destroy. Os 5 ECR e a role/policy do CI foram criados no console e depois adotados por blocos import.

### Arquivos-chave

| Caminho | Papel |
|---|---|
| `terraform/README.md` | Visão das 3 camadas, chaves de estado, parâmetros de conta, ordem base → imagens → cluster → k8s e validação offline |
| `terraform/backend.tf` | Versão mínima (>= 1.11.0), provider aws >= 5.46 e backend S3 parcial com key phase4/prod/base.tfstate, encrypt e use_lockfile (mesmo padrão em cluster/backend.tf e k8s/backend.tf) |
| `terraform/backend.hcl.example` | Modelo do backend.hcl local (bucket e região com sentinela); os reais são ignorados por terraform/.gitignore |
| `terraform/providers.tf` | Provider AWS com allowed_account_ids = [var.expected_aws_account_id] e default_tags (repetido em cluster/ e k8s/) |
| `terraform/main.tf` | Composição da base: módulo VPC da comunidade (~> 5.0), ecr, messaging e iam_ci (ARNs do ECR passados à policy do CI; ARN previsível do cluster passado ao self-healing) |
| `terraform/variables.tf` | Região us-east-2, AZs, CIDRs, NAT liga/desliga, serviços, tabela, mutabilidade do ECR, identidade GitHub (repo, IDs imutáveis, branch), create_github_oidc_provider e import_manual_resources |
| `terraform/imports.tf` | Blocos import condicionais que adotam no estado os 5 ECR, a role, a policy e o attachment do CI criados no console |
| `terraform/outputs.tf` | Outputs da base consumidos por cluster/k8s, GitOps e GitHub Variables (VPC, subnets, URLs ECR, SQS, DynamoDB, roles do CI e do self-healing) |
| `terraform/modules/iam-ci/main.tf` | Provedor OIDC do GitHub (criar ou ler), trust com subject imutável + branch main, role/policy de push no ECR, role do self-healing só com eks:DescribeCluster |
| `terraform/modules/iam-ci/tests/trust.tftest.hcl` | 10 casos de terraform test offline (provider apontado para 127.0.0.1:9) que provam a trust OIDC e o menor privilégio |
| `terraform/modules/eks/main.tf` | Cluster EKS, roles do control plane e dos nós, OIDC do cluster (base do IRSA), node group ON_DEMAND, IRSA do EBS CSI e 5 addons gerenciados |
| `terraform/modules/rds/main.tf` | N instâncias PostgreSQL 16 a partir de um mapa, SG restrito ao SG do cluster, random_password e segredo JSON com DATABASE_URL no Secrets Manager |
| `terraform/modules/messaging/main.tf` | Fila SQS com DLQ (redrive 5) e SSE; tabela DynamoDB PAY_PER_REQUEST com SSE |
| `terraform/modules/ecr/main.tf` | Um repositório <svc>-service por serviço, scan_on_push, AES256, force_delete e lifecycle de 10 imagens |
| `terraform/modules/irsa/main.tf` | Roles IRSA por ServiceAccount/namespace, com policies por ARN (evaluation publica na SQS; analytics consome a SQS e grava no DynamoDB) |
| `terraform/modules/elasticache/main.tf` | Redis em replication group de 1 nó, cifrado em repouso, TLS em trânsito por variável (desligado) |
| `terraform/cluster/main.tf` | Composição da camada cluster (eks, rds, elasticache, irsa) e nota de custo/destroy por sessão |
| `terraform/cluster/data.tf` | terraform_remote_state da base (VPC, subnets, ARNs de SQS e DynamoDB) |
| `terraform/cluster/self-healing.tf` | aws_eks_access_entry da role do self-healing mapeada a um grupo Kubernetes próprio (RBAC no gitops) |
| `terraform/cluster/variables.tf` | Versão do K8s (1.34), tipo/tamanho dos nós, classe RDS, mapa de bancos, tipo do Redis, state_bucket/state_region |
| `terraform/k8s/providers.tf` | Providers kubernetes e helm configurados pelo estado do cluster, com token via exec 'aws eks get-token' |
| `terraform/k8s/secrets.tf` | Namespace da app e os 5 Secrets das aplicações (DATABASE_URL vindo do remote state, senhas geradas, ignore_changes no Secret com dono duplo) |
| `terraform/k8s/observability.tf` | Namespace observability, Secrets do Grafana/New Relic/PagerDuty/Slack/dispatch e Application app-of-apps da observabilidade |
| `terraform/k8s/argocd.tf` | Instalação do ArgoCD via helm_release (chart 7.7.23 + imagem v2.13.9), Secret opcional de repositório e Application com prune/selfHeal; documenta o apply em 2 etapas |
| `terraform/k8s/storageclass.tf` | StorageClass gp3 padrão (EBS CSI, WaitForFirstConsumer, encrypted, reclaim Delete) |
| `terraform/k8s/variables.tf` | Versões do chart/imagem do ArgoCD, repo/branch/path GitOps e as variáveis sensíveis dos SaaS, com validações de formato |
| `.github/workflows/terraform-check.yml` | CI sem credenciais AWS: fmt, init -backend=false e validate nas 3 raízes + terraform test do iam-ci (Terraform 1.16.0) |
| `.gitignore` | Ignora tfstate, .terraform/, *.tfvars (exceto exemplos), planos, .env, chaves e kubeconfig; mantém os lockfiles versionados |
| `.env.example` | Valores fictícios só para o Docker Compose local; não lista as chaves SaaS/tokens que a camada k8s exige |
| `infra/postgres-app/01-init-multi-db.sh` | Script de init do PostgreSQL local do Compose (cria o 2º banco e aplica schemas); não é IaC de nuvem |
| `gitops/SECRETS-CONTRATO.md` | Contrato de nomes/chaves entre os Secrets criados pelo Terraform e os consumidores no GitOps |
| `00_COLAB_IA/02_TRABALHO/RELATORIO_TERRAFORM_BACKEND_2026-10-22_v01.md` | Explicação do backend parcial, lock S3, lockfiles e limites do guard de conta; pontos de atenção |
| `00_COLAB_IA/02_TRABALHO/GUIA_CONTAS_E_ACESSOS_FASE4_2026-10-28_v01.md` | Preparo das contas AWS/GitHub/New Relic/PagerDuty/Slack, Variables do GitHub e o que é segredo e o que não é |
| `00_COLAB_IA/02_TRABALHO/role-github-oidc-2026-10-28_v01/LEIA-ME.md` | Passo a passo da criação MANUAL (console) do provedor OIDC, da policy e da role do CI, além da questão do subject imutável |
| `00_COLAB_IA/02_TRABALHO/TOKENS_GITHUB_PREIMPLANTACAO_2026-11-04_v01.md` | Dois PATs fine-grained (leitura para o ArgoCD; dispatch para o Grafana) guardados no .env e mapeados para TF_VAR_* |
| `00_COLAB_IA/02_TRABALHO/PASSO2_CONTAS_SAAS_2026-11-01_v01.md` | Obtenção das chaves New Relic/PagerDuty/Slack e onde cada segredo é usado |
| `00_COLAB_IA/02_TRABALHO/PREPARACAO_B3_2026-11-04_v01.md` | Fatos da conta (plano FREE, cota de 5 vCPU, elegibilidade), plano real da base e estimativa de custo pela Price List |
| `00_COLAB_IA/02_TRABALHO/GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md` | Runbook real de deploy (ordem dos applies, passos manuais, seed) e de destroy com plano salvo |
| `00_COLAB_IA/02_TRABALHO/ENCERRAMENTO_AWS_2026-11-12_v01.md` | Destroy completo (19/36/37 recursos), limpeza de EBS e remoção do bucket; arquivo local NÃO versionado que contém o ID da conta em texto |
| `00_COLAB_IA/02_TRABALHO/AUDITORIA_CUSTOS_AWS_2026-11-13_v01.md` | Custo real por serviço (US$ 33,55 antes de créditos) e verificação de que não sobrou recurso |
| `00_COLAB_IA/02_TRABALHO/ANALISE_COMPLETA_FASE4_2026-10-31_v01.md` | Achados TFC-01..12 (sizing, versão do EKS, autoscaler, EBS órfão, endpoint público, Redis sem TLS, segredos no state, IRSA, egress, NAT) |
| `00_COLAB_IA/02_TRABALHO/validacao-local-encerramento-2026-11-12/operar.py` | Script local (ignorado) que aplica só planos com hash conferido e conta verificada por STS; junto com encerrar_backend.py e inventario.py |
| `00_COLAB_IA/DECISOES.md` | Decisões F3-D-003 (conta pessoal, não Academy), F3-D-009 (tags), F3-D-010 (módulos), F3-D-017 (camadas), F3-D-018 (sem ESO) e D-026 (encerramento) |

### Decisões técnicas da Fase 4

- Conta AWS pessoal, não AWS Academy/Learner Lab/LabRole, para poder criar IAM, roles, policies e OIDC por Terraform; a conta da Fase 4 é nova, no plano FREE com créditos (DECISOES.md F3-D-003; terraform/modules/eks/main.tf cabeçalho; CREDITOS_AWS_2026-11-13_v01.md)
- Região us-east-2 com AZs us-east-2a/us-east-2b, repetida como variável em cada raiz (terraform/variables.tf; terraform/cluster/variables.tf; terraform/k8s/variables.tf)
- Terraform required_version >= 1.11.0; o CI fixa 1.16.0 (terraform/backend.tf; .github/workflows/terraform-check.yml)
- Backend S3 parcial: key fixa no código, bucket/região em backend.hcl local ignorado, encrypt=true e use_lockfile=true (lock nativo do S3 via objeto .tflock, sem tabela DynamoDB) (terraform/backend.tf; terraform/cluster/backend.tf; terraform/k8s/backend.tf; terraform/.gitignore)
- Bucket de estado no namespace regional da conta (sufixo -an), com versionamento, bloqueio de acesso público, SSE-S3 e policy que nega acesso sem TLS, criado fora do Terraform (LOG_DE_TRABALHO.md 2026-10-28/30; PREPARACAO_B3_2026-11-04_v01.md)
- Três root modules independentes, base/cluster/k8s, ligados por terraform_remote_state: o cluster é destruído sem levar os ECR, e a camada k8s é separada porque seus providers dependem do cluster (DECISOES.md F3-D-017; terraform/cluster/data.tf; terraform/k8s/data.tf)
- Guard de conta: allowed_account_ids = [var.expected_aws_account_id], sem default e com validação de 12 dígitos (terraform/providers.tf; terraform/variables.tf; idem em cluster/ e k8s/)
- default_tags no provider AWS das 3 raízes: project=fiap e phase=4, chaves em minúsculas porque tag é case-sensitive (terraform/providers.tf; terraform/variables.tf; DECISOES.md F3-D-009)
- Versões: aws >= 5.46 travado em 6.62.0 (base e iam-ci) e 6.63.0 (cluster e k8s); random 3.9.0; tls 4.4.0; kubernetes ~> 3.0 (3.2.1); helm ~> 3.0 (3.3.0); módulo VPC ~> 5.0, resolvido para 5.21.0 (.terraform.lock.hcl de cada raiz; terraform/main.tf; terraform/.terraform/modules/modules.json)
- Módulos híbridos: só a VPC é da comunidade (terraform-aws-modules/vpc/aws); ecr, messaging, iam-ci, eks, rds, elasticache e irsa são próprios (DECISOES.md F3-D-010; terraform/modules/*)
- Rede: VPC 10.0.0.0/16, 2 subnets privadas /24 e 2 públicas /24, NAT único controlado por enable_nat_gateway, DNS ligado e tags de subnet para ELB; sem Ingress/LB, com acesso por port-forward (terraform/main.tf; terraform/variables.tf; DECISOES.md F3-D-012)
- EKS: versão 1.34, endpoint público e privado sem public_access_cidrs, authentication_mode API_AND_CONFIG_MAP, bootstrap_cluster_creator_admin_permissions=true, sem upgrade_policy e sem logs do control plane (terraform/modules/eks/main.tf; terraform/cluster/variables.tf)
- Node group gerenciado ON_DEMAND m7i-flex.large (2 vCPU, 8 GiB), default min 1/desired 2/max 4; o tfvars local usou max 2 por causa da cota de 5 vCPU; sem Cluster Autoscaler (terraform/cluster/variables.tf; terraform/cluster/terraform.tfvars local; PREPARACAO_B3_2026-11-04_v01.md)
- Addons EKS gerenciados (e não via Helm): vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver com role IRSA própria e metrics-server (terraform/modules/eks/main.tf)
- RDS: mapa de bancos (auth_db, flags_db), PostgreSQL 16, db.t3.micro, gp3 de 20 GB com autoscaling até 40 GB, cifrado, privado, single-AZ, backup de 1 dia, skip_final_snapshot=true, deletion_protection=false; SG libera 5432 só a partir do SG do cluster; o 3º banco roda em StatefulSet (terraform/modules/rds/main.tf; terraform/cluster/variables.tf; DECISOES.md F3-D-015)
- Senhas dos RDS geradas por random_password (24 caracteres alfanuméricos, sem especiais para não quebrar a URL), gravadas no Secrets Manager <projeto>/<svc>-service com recovery_window_in_days=0 e expostas no output sensível database_urls (terraform/modules/rds/main.tf; terraform/cluster/outputs.tf)
- SQS Standard <projeto>-events com DLQ (maxReceiveCount 5, retenção de 14 dias), SSE gerenciado pela SQS, long polling de 20 s e visibility de 30 s; DynamoDB PAY_PER_REQUEST com SSE, deletion_protection=false e sem PITR declarado (terraform/modules/messaging/main.tf)
- ECR: um repositório <svc>-service por serviço, MUTABLE, scan_on_push, AES256, force_delete=true e lifecycle que mantém 10 imagens (terraform/modules/ecr/main.tf; terraform/variables.tf)
- ElastiCache: replication group de 1 nó cache.t3.micro, default.redis7, cifrado em repouso, TLS em trânsito desligado por padrão; o output redis_url acompanha o esquema redis/rediss (terraform/modules/elasticache/main.tf; terraform/modules/elasticache/outputs.tf)
- GitHub OIDC: create_github_oidc_provider=false na conta da Fase 4, pois o provedor já existia e é lido por data source; trust StringEquals no aud e no sub com o subject imutável (owner@id/repo@id) e a branch main; role do CI só com push/pull nos ECR do projeto (terraform/modules/iam-ci/main.tf; terraform/terraform.tfvars.example)
- Self-healing: role separada, com trust idêntica e somente eks:DescribeCluster no ARN do cluster; no Kubernetes, acesso por aws_eks_access_entry ligado a um grupo próprio cujo RBAC fica no gitops (terraform/modules/iam-ci/main.tf; terraform/cluster/self-healing.tf)
- IRSA: provedor OIDC do cluster criado no módulo eks; módulo irsa com trust amarrada a namespace + ServiceAccount + aud e policies restritas aos ARNs da fila/tabela; nomes das roles fixos porque o overlay GitOps os referencia (terraform/modules/irsa/main.tf; terraform/cluster/main.tf)
- Segredos sem External Secrets Operator: a camada k8s cria kubernetes_secret_v1 com valores do remote state, de random_password e de variáveis sensíveis TF_VAR_* validadas por formato; o Secret com dono duplo (SERVICE_API_KEY) usa ignore_changes=[data] (terraform/k8s/secrets.tf; terraform/k8s/observability.tf; terraform/k8s/variables.tf; gitops/SECRETS-CONTRATO.md; DECISOES.md F3-D-018)
- ArgoCD via helm_release: chart 7.7.23 fixo com imagem v2.13.9 (correção da CVE-2025-55190); Dex, ApplicationSet e notifications desligados; server.insecure; reconciliação a cada 30 s; Application com prune/selfHeal, retry e ignoreDifferences de /spec/replicas para os Deployments com HPA (terraform/k8s/argocd.tf; terraform/k8s/variables.tf)
- StorageClass gp3 marcada como padrão, provisioner ebs.csi.aws.com, WaitForFirstConsumer, encrypted e reclaim Delete (terraform/k8s/storageclass.tf)
- Recursos criados no console adotados por blocos import com for_each, ligados/desligados por import_manual_resources; description da policy em ignore_changes para evitar recriação (terraform/imports.tf; terraform/modules/iam-ci/main.tf)
- Validação de IaC sem nuvem no CI: fmt -check, init -backend=false, validate nas 3 raízes e terraform test do iam-ci, sem permissão id-token (.github/workflows/terraform-check.yml)
- Operação sempre com plano salvo, revisão e apply do próprio plano, inclusive no destroy, que segue a ordem reversa k8s → cluster → base e remove o bucket por último (GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md; ENCERRAMENTO_AWS_2026-11-12_v01.md)

### O que reaproveitar na Fase 5

| Item | Como reaproveitar |
|---|---|
| Estrutura em 3 raízes (base/cluster/k8s) com terraform_remote_state e backend S3 parcial com use_lockfile (terraform/backend.tf, terraform/cluster/data.tf, terraform/k8s/data.tf, *.backend.hcl.example) | Manter o desenho; trocar o prefixo das chaves (ex.: phase5/prod/...), o nome do projeto e os exemplos de backend.hcl/tfvars. Não copiar .terraform/, *.tfplan, backend.hcl nem terraform.tfvars locais da Fase 4 |
| Guard de conta e default_tags nos providers (terraform/providers.tf e equivalentes em cluster/ e k8s/; variable default_tags) | Manter allowed_account_ids e trocar o mapa de tags para Project=SolidaryTech, Environment=Production, CostCenter=NGO-Core (REQ-OBR-19), respeitando a caixa exata das chaves |
| Chamada do módulo VPC da comunidade (terraform/main.tf, bloco module "vpc") | Copiar como está (2 AZs, NAT único, DNS, tags de subnet); deixar região e AZs como variáveis, o que ajuda numa eventual região de DR |
| Módulo ECR (terraform/modules/ecr) | Copiar e passar services = ["ngo", "donation", "volunteer"]; os nomes viram <svc>-service |
| Módulo messaging (terraform/modules/messaging) | Adaptar para a fila Standard do donation-service (com DLQ) e para a tabela SolidaryTechVolunteers com hash_key volunteer_id (String), como pede o README da Fase 5; avaliar PITR (RPO do DR) e GSI (REQ-BON-03) |
| Módulo RDS (terraform/modules/rds) | Reusar o mapa databases = { ngo = "ngo_db", donation = "donation_db" }, mantendo o SG restrito ao SG do cluster, a criptografia e o Secrets Manager; revisar username e nomes dos segredos |
| Módulo EKS (terraform/modules/eks) e composição em terraform/cluster/main.tf | Manter os addons, o OIDC do cluster e o IRSA do EBS CSI; escolher uma versão em suporte padrão e adicionar upgrade_policy STANDARD; dimensionar os nós pela cota de vCPU; considerar logs do control plane e public_access_cidrs |
| Módulo IRSA (terraform/modules/irsa) | Manter o padrão de trust (namespace + SA + aud) e reescrever as policies, hoje fixas nas chaves evaluation/analytics: donation-service com sqs:SendMessage na fila; volunteer-service com as ações DynamoDB que o código usa, limitadas à tabela |
| Módulo iam-ci e seus testes (terraform/modules/iam-ci, tests/trust.tftest.hcl) | Trocar o repositório para tech-challenge-05 e obter os IDs numéricos do owner e do repo; passar os ARNs dos 3 ECR; decidir create_oidc_provider; atualizar os valores esperados nos 10 casos de teste |
| Access entry do self-healing (terraform/cluster/self-healing.tf) | Copiar se o self-healing da Fase 4 for reaplicado (Q-09 do mapa); ajustar o nome do grupo para o RBAC novo |
| ArgoCD via Helm e Applications (terraform/k8s/argocd.tf) | Trocar repoURL/path/branch para o tech-challenge-05, os nomes dos Deployments no ignoreDifferences e o namespace; manter chart e imagem fixos, reconferindo versão e CVE; manter o procedimento de apply em 2 etapas |
| Secrets das aplicações (terraform/k8s/secrets.tf) | Reescrever para os 3 serviços: DATABASE_URL de ngo e donation vindo do remote state; nenhuma credencial AWS (IRSA); volunteer sem segredo de banco; atualizar o contrato em gitops |
| Secrets e Application da observabilidade (terraform/k8s/observability.tf e as variáveis sensíveis com validação em terraform/k8s/variables.tf) | Copiar quase integral; ajustar os nomes do repositório/token e os namespaces |
| StorageClass gp3 padrão (terraform/k8s/storageclass.tf) | Copiar; acrescentar tags nos volumes criados pelo CSI para que os discos dos PVCs entrem no FinOps |
| Módulo ElastiCache (terraform/modules/elasticache) | Copiar somente se o bônus REQ-BON-04 for adotado (hoje nenhum serviço da SolidaryTech usa cache) |
| Imports de recursos clicados (terraform/imports.tf) | Não reaproveitar: REQ-OBR-03 da Fase 5 proíbe infraestrutura criada no console; usar apenas para importar, se for o caso, o provedor OIDC preexistente |
| Workflow Terraform Check (.github/workflows/terraform-check.yml) | Copiar, ajustando os caminhos e o nome do módulo testado |
| Regras Terraform do .gitignore e terraform/.gitignore | Copiar (tfstate, .terraform/, tfvars reais, planos, backend.hcl, .env e kubeconfig) |
| Runbook de deploy/destroy e scripts de operação segura (GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md; validacao-local-encerramento-2026-11-12/operar.py, encerrar_backend.py, inventario.py) | Adaptar a sequência e os guardas (STS, hash do plano, estados vazios antes de apagar o bucket), parametrizando conta e bucket por variável em vez de hardcode |

### Riscos e pegadinhas

- Conflito com a Fase 5: REQ-OBR-03 exige zero infraestrutura clicada. Na Fase 4, o bucket de estado, o provedor OIDC do GitHub, a role/policy do CI, os 5 ECR e o AWS Budget nasceram no console/CLI (os ECR e o IAM do CI foram importados depois). É preciso uma raiz de bootstrap ou outra solução (terraform/imports.tf; role-github-oidc-2026-10-28_v01/LEIA-ME.md)
- O primeiro apply da camada k8s não funciona direto: kubernetes_manifest valida o CRD Application no plan, antes de o Helm instalá-lo. Exige 'apply -target=helm_release.argocd' e depois o apply completo, em todo cluster novo (terraform/k8s/argocd.tf)
- Subject OIDC imutável: a organização usa o formato repo:owner@ID/repo@ID:ref:refs/heads/main; o padrão antigo repo:org/repo:* não casava e quase restaurou uma trust incompatível (role-github-oidc-2026-10-28_v01/LEIA-ME.md; terraform/modules/iam-ci/main.tf)
- Nome do cluster (togglemaster) foi confundido com o nome da role (togglemaster-eks-cluster), gerando ARN errado na policy do self-healing; corrigido antes do apply (PREPARACAO_B3_2026-11-04_v01.md)
- count não aceita valor sensível: foi preciso nonsensitive(var.github_token != "") no Secret do repositório do ArgoCD (terraform/k8s/argocd.tf)
- Em aws_iam_policy, description força recriação; como a policy foi importada, a descrição ficou em ignore_changes (terraform/modules/iam-ci/main.tf)
- import_manual_resources precisa voltar a false depois de um destroy; senão o plan falha com 'Cannot import non-existent remote object' (terraform/imports.tf)
- Limites do plano FREE: t3.medium recusada e 3ª instância RDS recusada na conta da Fase 3; na conta da Fase 4, cota de 5 vCPU On-Demand, o que deu no máximo 2 nós de 2 vCPU. A memória ficou apertada com a stack de observabilidade (TFC-01) e a solução foi usar nós de 8 GiB (PREPARACAO_B3_2026-11-04_v01.md; DECISOES.md F3-D-015/F3-D-016; ANALISE_COMPLETA_FASE4 TFC-01)
- EKS 1.34 sai do suporte padrão em 2026-12-01/02 (data citada nos arquivos) e o código não tem upgrade_policy STANDARD. No suporte estendido, o control plane passa de US$ 0,10/h para US$ 0,60/h (terraform/modules/eks/main.tf; ANALISE_COMPLETA_FASE4 TFC-03; DECISOES.md F3-SN-10)
- Sem NAT, os nós em subnets privadas não baixam imagens (ImagePullBackOff/NodeCreationFailure) e os alertas não saem para New Relic, PagerDuty, Slack e GitHub. A camada cluster não tem precondition verificando o NAT, e o exemplo da base vem com enable_nat_gateway=false (terraform/terraform.tfvars.example; ANALISE_COMPLETA_FASE4 TFC-12)
- Segredos em texto puro no state (senhas RDS, URLs, chaves SaaS na camada k8s) e nos *.tfplan; sensitive só oculta no terminal. O acesso ao bucket deve ser restrito. A pasta da Fase 4 ainda tem backend.hcl, terraform.tfvars, .terraform/ e *.tfplan locais (ignorados): não copiá-los para a Fase 5 (RELATORIO_TERRAFORM_BACKEND §10; ANALISE_COMPLETA_FASE4 TFC-09)
- allowed_account_ids só protege o provider AWS; não protege o backend S3, o terraform_remote_state nem o 'aws eks get-token' usado pelos providers kubernetes/helm (RELATORIO_TERRAFORM_BACKEND §7)
- No destroy, os PVCs (PostgreSQL, Prometheus e Loki) geram volumes EBS que podem ficar órfãos e não recebem default_tags. Foi preciso remover antes as Applications pai do ArgoCD (finalizers), conferir PVC/PV/EBS antes de derrubar o cluster/CSI e procurar volumes 'available' manualmente (ENCERRAMENTO_AWS_2026-11-12_v01.md; ANALISE_COMPLETA_FASE4 TFC-05)
- O EKS não marca a StorageClass gp2 como padrão: sem a gp3 padrão e sem storageClassName no manifesto, o PVC fica Pending para sempre (terraform/k8s/storageclass.tf)
- Ligar TLS no Redis sem trocar REDIS_URL para rediss:// derruba o serviço no boot (CrashLoopBackOff) (terraform/modules/elasticache/variables.tf)
- selfHeal do ArgoCD e HPA brigam por replicas; foram necessários ignoreDifferences em /spec/replicas e RespectIgnoreDifferences=true (terraform/k8s/argocd.tf)
- O seed do schema dos RDS e a gravação da chave de serviço foram feitos com 'kubectl run' e 'kubectl apply' manuais. Repetir isso choca com REQ-OBR-02 (zero deploy manual via kubectl) da Fase 5 (GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md; terraform/k8s/secrets.tf)
- Lockfiles divergem entre raízes (aws 6.62.0 na base/iam-ci e 6.63.0 em cluster/k8s), e o metadado 'constraints' do lock da k8s está desatualizado em relação a ~> 3.0 (terraform/.terraform.lock.hcl; terraform/k8s/.terraform.lock.hcl; RELATORIO_TERRAFORM_BACKEND §7)
- Há comentários herdados da conta da Fase 3 (custo/hora, crédito restante, 'esta conta recusa', aprovação do professor, IDs de decisões que colidem com os da Fase 4); levar isso ao relatório geraria afirmações falsas (ANALISE_COMPLETA_FASE4 TFC-06; terraform/cluster/main.tf)
- Node group com max_size, mas sem Cluster Autoscaler: os nós não escalam sozinhos, o que pesa para o bônus REQ-BON-02 (ANALISE_COMPLETA_FASE4 TFC-04)
- O endpoint público da API do EKS fica aberto a 0.0.0.0/0, sem logs de audit/authenticator; o Redis não tem AUTH/TLS; os SGs de RDS/Redis têm egress 0.0.0.0/0 desnecessário (ANALISE_COMPLETA_FASE4 TFC-07/08/11)
- Destroy interativo é perigoso quando se colam blocos de comandos (uma linha pode responder ao 'yes'); usar sempre plan -destroy -out e aplicar o plano salvo (GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md Parte 4)
- Higiene: o ID da conta aparece em texto em arquivos locais não versionados e não ignorados (ex.: 00_COLAB_IA/02_TRABALHO/ENCERRAMENTO_AWS_2026-11-12_v01.md) e nos scripts de encerramento. Além disso, por decisão, entrou no repositório público via overlay GitOps (ARNs IRSA e URL da SQS)
- .env.example só cobre o Compose local; não documenta as variáveis que a camada k8s exige (NEW_RELIC_LICENSE_KEY, PAGERDUTY_INTEGRATION_KEY, SLACK_WEBHOOK_URL, GITHUB_DISPATCH_TOKEN e GITHUB_ARGOCD_TOKEN), citadas só em terraform/k8s/terraform.tfvars.example e no TOKENS_GITHUB_PREIMPLANTACAO
- Custo de referência: US$ 0,409/h com tudo ligado (Price List, us-east-2, 2026-11-04). O consumo real de 09 a 12/11 foi de US$ 33,55, sendo os maiores itens EC2 (14,97), EKS (7,83), EC2-Other/NAT/EBS (5,40) e RDS (3,31). O Budget foi criado fora do Terraform de propósito, para não ser apagado no destroy (PREPARACAO_B3_2026-11-05_v02.md; AUDITORIA_CUSTOS_AWS_2026-11-13_v01.md; LOG_DE_TRABALHO.md 2026-11-05)
- O trial do PagerDuty (14 dias) limitou a janela de gravação; no plano Free, a linha 'Events' aparece como não incluída. Isso afeta o caminho alerta → incidente, que depende de um segredo injetado pelo Terraform (PASSO2_CONTAS_SAAS_2026-11-01_v01.md; LOG_DE_TRABALHO.md 2026-10-30)

### Dependências externas

- Conta AWS pessoal, não Academy, no plano FREE com créditos; na Fase 4, a conta tinha cerca de US$ 126,45 restantes em 2026-11-13 e o plano vale até 2027-04-20. Saldo e plano são consultados com 'aws freetier get-account-plan-state' (CREDITOS_AWS_2026-11-13_v01.md)
- Identidade IAM humana de provisionamento (usuário IAM, não root) usada por perfil local da AWS CLI; a policy exata anexada a ela não foi encontrada nos arquivos (GUIA_CONTAS_E_ACESSOS; LOG_DE_TRABALHO.md 2026-10-28)
- Cota EC2 On-Demand Standard (5 vCPU na conta da Fase 4) e elegibilidade dos tipos de instância no plano FREE
- Bucket S3 de estado existente antes do 'terraform init', com versionamento, bloqueio público, SSE-S3 e policy só TLS; nome e região informados em backend.hcl e em state_bucket/state_region (não versionados)
- AWS Budgets: orçamento com alertas por e-mail, configurado fora do Terraform (os e-mails não ficam em arquivo versionado)
- GitHub: organização e repositório com Actions; Repository Variables AWS_REGION, ECR_REGISTRY, AWS_ROLE_ARN, AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME; OIDC com subject imutável (IDs numéricos do owner e do repo); nenhum secret AWS no GitHub
- GitHub fine-grained PATs restritos ao repositório: token de dispatch (Contents read/write) para o Grafana disparar repository_dispatch e, só se o repo for privado, token de leitura para o ArgoCD; ficam no .env local e viram TF_VAR_github_dispatch_token e TF_VAR_github_token
- New Relic: license key do tipo Ingest-License (40 caracteres), passada como TF_VAR_new_relic_license_key; endpoint OTLP conforme a região da conta (US na Fase 4)
- PagerDuty: Integration Key da Events API v2 (32 caracteres alfanuméricos, não puramente numérica), passada como TF_VAR_pagerduty_integration_key; serviço e política de escalonamento configurados na UI
- Slack: URL de Incoming Webhook do canal de incidentes, passada como TF_VAR_slack_webhook_url (a URL é o próprio segredo)
- Registros públicos: Terraform Registry (providers e módulo VPC), repositório Helm argoproj.github.io/argo-helm e imagem quay.io/argoproj/argocd
- Ferramentas locais: Terraform >= 1.11 (1.16.0 no CI), AWS CLI no PATH (exigida pelo exec dos providers kubernetes/helm), kubectl, gh CLI, Git Bash e Python para os scripts de conferência

### Passos que ficaram manuais na Fase 4 (a eliminar na Fase 5)

- Criar o bucket S3 de estado (console/CLI) com versionamento, bloqueio público, SSE-S3 e policy TLS-only antes do primeiro init; na Fase 3, as tags do bucket foram postas à mão
- Criar backend.hcl e terraform.tfvars locais nas 3 raízes a partir dos .example, informando conta, bucket, região, NAT e tamanho dos nós
- Criar no console o provedor OIDC do GitHub, a policy de push no ECR, a role do CI e os 5 repositórios ECR. Os quatro últimos foram depois adotados por imports.tf; o provedor OIDC ficou fora do Terraform (data source) e continua na conta após o destroy
- Criar o AWS Budget com 5 alertas (25/50/75/100% real e 100% previsto) via CLI, fora do Terraform
- Cadastrar Repository Variables no GitHub: AWS_REGION, ECR_REGISTRY e AWS_ROLE_ARN à mão; AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME via 'gh variable set' após o apply da base
- Rodar 'aws eks update-kubeconfig' após o apply do cluster
- Preencher o overlay GitOps (patches de endpoints e IRSA) com os outputs do Terraform via sed, validar com o script checar_overlay.py e fazer commit/push
- Exportar as TF_VAR_* sensíveis a partir do .env local na mesma janela, antes de cada plan, apply e destroy da camada k8s
- Fazer o apply da camada k8s em 2 etapas: '-target=helm_release.argocd', esperar o CRD ficar Established e depois o plan/apply completo
- Promover dev → PR → main e esperar os pipelines publicarem as imagens e gravarem as tags no overlay antes de criar as Applications
- Seed pós-deploy: aplicar init.sql nos RDS via 'kubectl run psql', criar a SERVICE_API_KEY em POST /admin/keys, sobrescrever o Secret do evaluation com kubectl apply, fazer rollout restart e criar flags de exemplo
- Ler as senhas iniciais do ArgoCD e do Grafana por kubectl e abrir os túneis por port-forward (não há Ingress/LB)
- No destroy: plan -destroy salvo por camada em ordem reversa; remover antes as Applications pai do ArgoCD; conferir PVC/PV e volumes EBS 'available' e apagá-los; esvaziar versões e apagar o bucket por script depois de validar os estados vazios; limpar os caches .terraform e os *.tfplan (a limpeza local não foi feita: arquivos ainda presentes na pasta da Fase 4)
- Conferências fora do código: cota de vCPU, elegibilidade dos tipos no plano FREE, versão do EKS em suporte padrão, saldo de créditos e inventário multi-região pós-destroy
- Criar as contas SaaS (New Relic, PagerDuty, Slack), as chaves e integrações e os PATs do GitHub pela interface de cada serviço

### Dúvidas levantadas pela leitura (histórico)

- Qual conta AWS a Fase 5 vai usar: a mesma conta pessoal da Fase 4 (plano FREE, cerca de US$ 126 de crédito em 13/11, cota de 5 vCPU, provedor OIDC do GitHub criado no console ainda existente) ou outra? Qual o teto de gasto aceitável, e podemos pedir aumento da cota de vCPU se for preciso?
- Região primária: manter a us-east-2 da Fase 4 ou usar a us-east-1 dos exemplos do README da Fase 5? Se o DR for a Opção B (ambiente espelho via Terraform), qual será a região secundária?
- Para cumprir 'zero infraestrutura clicada' (REQ-OBR-03), você aceita uma raiz Terraform de bootstrap (com estado local) que crie o bucket de estado e o provedor OIDC do GitHub? Se a conta da Fase 4 for reutilizada, o provedor OIDC preexistente deve ser importado para o Terraform ou apenas consultado?
- O repositório tech-challenge-05 vai ficar público ou privado durante o deploy? Isso define se o ArgoCD precisa de token de leitura.
- Ciclo de vida do ambiente: subir só nas janelas de teste/gravação e destruir logo depois, como na Fase 4, ou manter parte da infraestrutura (ex.: base com ECR) ligada de forma contínua?

<a id="2-cicd"></a>
## 2. CI/CD DevSecOps e GitOps

Na Fase 4 o CI/CD fica num monorepo com 11 workflows do GitHub Actions. Cinco chamadores finos, um por serviço (auth e evaluation em Go; flag, targeting e analytics em Python), delegam via workflow_call a dois reutilizáveis por stack (_ci-go.yml e _ci-python.yml). Completam o conjunto GitOps Check, Terraform Check, Integração em Compose e Self-healing. Os chamadores disparam em push para main/dev, em PR para main/dev (com filtro de caminho services/<svc>/**, o próprio arquivo e o reutilizável) e em workflow_dispatch. O concurrency por serviço e ref cancela execuções antigas, exceto na main. Nos reutilizáveis, build/testes, lint, SAST e SCA rodam em paralelo. Em PR ou dispatch, o job image-scan constrói e escaneia a imagem sem publicar. Em push na main, o job image (needs dos quatro) refaz o build, passa o Trivy CRITICAL na imagem, assume uma role AWS por OIDC e faz push no ECR com as tags v1.0.0-<sha7> e latest. O job gitops, único com contents: write, roda `kustomize edit set image` em gitops/overlays/prod/kustomization.yaml e comita direto na main como github-actions[bot] com [skip ci]; usa um laço de 5 tentativas fetch/reset --hard/edit/commit/push. Três barreiras evitam loop: push com GITHUB_TOKEN não dispara workflows, a mensagem leva [skip ci] e os filtros de caminho dos serviços não incluem gitops/**. O ArgoCD é instalado por helm_release em terraform/k8s/argocd.tf e recebe duas Applications criadas pelo Terraform: togglemaster (Kustomize do overlay prod, branch main) e observability (app of apps com 4 Applications Helm multi-source e sync waves); ambas usam sync automático com prune, selfHeal e retry, polling de 30 s e não usam ApplicationSet. Requests/limits e probes HTTP /health ficam em cada gitops/base/<svc>/deployment.yaml; só evaluation e analytics têm HPA, e o ArgoCD ignora /spec/replicas desses dois Deployments. Os segredos de aplicação não passam pelo Git: o Terraform cria os Secrets do Kubernetes (contrato em gitops/SECRETS-CONTRATO.md), os pods acessam a AWS por IRSA e o CI por OIDC, sem chave estática. O fluxo humano é dev → PR → main; o robô comita tags direto na main e não havia proteção de branch, então um check vermelho não bloqueava o merge e a dev precisava ser sincronizada após cada publicação.

### Arquivos-chave

| Caminho | Papel |
|---|---|
| `.github/workflows/_ci-go.yml` | Reutilizável Go: build/test, golangci-lint, gosec, Trivy fs, image-scan (PR), image (ECR via OIDC) e gitops (commit da tag) |
| `.github/workflows/_ci-python.yml` | Reutilizável Python: pip/compileall/pytest, flake8+pylint, bandit, Trivy fs, image-scan, image e gitops |
| `.github/workflows/auth-service.yml, evaluation-service.yml, flag-service.yml, targeting-service.yml, analytics-service.yml` | Chamadores por serviço: gatilhos, paths, teto de permissions, concurrency e input service |
| `.github/workflows/gitops-check.yml` | Em todo PR/push: render Kustomize, checagem do Grafana, testes do self-healing e varredura de segredos |
| `.github/workflows/terraform-check.yml` | fmt/validate das 3 camadas e terraform test do módulo iam-ci, sem AWS |
| `.github/workflows/compose-integration.yml` | Ensaio ponta a ponta dos 5 serviços em Docker Compose com Moto |
| `.github/workflows/self-healing.yml` | repository_dispatch do Grafana → OIDC → rollout restart com allowlist e cooldown |
| `gitops/base/kustomization.yaml` | Índice da base: namespace, labels, recursos e configMapGenerator otel-config |
| `gitops/base/<svc>/deployment.yaml` | Requests/limits, probes /health, envFrom de ConfigMap e secretKeyRef |
| `gitops/base/{evaluation,analytics}-service/hpa.yaml e serviceaccount.yaml` | HPA por CPU e ServiceAccount IRSA sem anotação na base |
| `gitops/base/self-healing-rbac.yaml` | Role/RoleBinding: só patch nos 5 Deployments para o grupo do self-healing |
| `gitops/overlays/prod/kustomization.yaml` | Overlay único; bloco images reescrito pelo CI; merge do otel-config |
| `gitops/overlays/prod/patches/irsa.yaml e endpoints.yaml` | ARNs IRSA e URLs SQS/Redis dependentes da conta (contêm ID de conta) |
| `gitops/observability/kustomization.yaml e applications/*.yaml` | App of apps da observabilidade: 4 Applications Helm multi-source + ConfigMaps do Grafana |
| `gitops/SECRETS-CONTRATO.md e gitops/README.md` | Contrato de nomes/chaves dos Secrets e guia do que preencher por conta |
| `terraform/k8s/argocd.tf` | helm_release do ArgoCD e Application togglemaster (prune, selfHeal, ignoreDifferences, retry) |
| `terraform/k8s/observability.tf` | Secrets da observabilidade e Application mãe observability |
| `terraform/k8s/secrets.tf` | Criação dos 5 Secrets da aplicação via provider kubernetes |
| `terraform/modules/iam-ci/main.tf e tests/trust.tftest.hcl` | Provedor OIDC, role do CI (push ECR) e role do self-healing, com testes da confiança |
| `terraform/modules/ecr/main.tf` | Repositórios ECR por serviço, scan on push e lifecycle |
| `terraform/cluster/self-healing.tf` | Access entry do EKS ligando a role do self-healing ao grupo Kubernetes |
| `scripts/gitops/validate.sh, check-grafana.py, test-check-grafana.py` | Validação do gitops/ (local e CI) |
| `scripts/security-check.sh` | Varredura de segredos por git grep |
| `scripts/self-healing/restart.sh e test-restart.sh` | Lógica do restart e 11 cenários com kubectl falso |
| `scripts/test-compose.sh e docker-compose.integration.yaml` | Ensaio integrado com Moto pinado por digest |
| `scripts/validate-all.sh` | Reprodução local do CI |
| `docs/CI-CD.md` | Documentação dos workflows e do fluxo dev → PR → main |
| `.trivyignore, .pylintrc, SECURITY.md, .gitattributes` | Política de exceções do Trivy, regras do pylint, política de credenciais e eol=lf para *.sh |

### Decisões técnicas da Fase 4

- Um chamador por serviço delega a um reutilizável por stack via workflow_call. O input único `service` resolve a pasta em services/, o repositório no ECR e o nome lógico da imagem no Kustomize (.github/workflows/*-service.yml, _ci-go.yml, _ci-python.yml).
- Gatilhos dos serviços: push em [main, dev] e pull_request para [main, dev], com paths [services/<svc>/**, o próprio workflow, o reutilizável], mais workflow_dispatch. Concurrency `ci-<svc>-${{ github.ref }}` com cancel-in-progress só fora da main (*-service.yml).
- Permissões: o chamador define o teto (id-token: write, contents: write). Os jobs image (id-token write + contents read), gitops (contents write) e image-scan (contents read) reduzem; build/lint/sast/sca não declaram permissions (_ci-*.yml).
- Portão de segurança: o job image tem needs [build, lint, sast, sca] e `if: push && refs/heads/main`. O image-scan roda em PR/dispatch sem needs e sem AWS. O job gitops tem needs [image] e não tem concurrency, de propósito (_ci-go.yml, _ci-python.yml).
- Go: setup-go@v5 com go-version-file do go.mod e cache por go.sum; `go build -v ./...` e `go test -count=1 -v ./...`; golangci-lint-action@v9 com golangci-lint v2.13.2 sem config; gosec v2.29.0 via go install com Go 1.25 fixo, `-severity high -confidence medium` (falha só em HIGH) (_ci-go.yml).
- Python 3.12, igual ao python:3.12-slim dos Dockerfiles: pip install -r requirements, `compileall -q .`, pytest só se houver tests/ ou test_*.py/*_test.py. flake8 7.5.0 bloqueia E9,F63,F7,F82 e o estilo sai com --exit-zero; pylint 4.1.3 usa `--rcfile=$GITHUB_WORKSPACE/.pylintrc` (fail-under 7.0, max-line-length 120); `bandit -r . -ll` falha em MÉDIO ou ALTO (_ci-python.yml, .pylintrc).
- SCA e scan de imagem com aquasecurity/trivy-action pinada por SHA (v0.36.0): scan-type fs (scan-ref services/<svc>) e image (tag local <svc>:scan), severity CRITICAL, exit-code 1, ignore-unfixed false e trivyignores .trivyignore. As exceções são nominais, com justificativa e data de revisão (_ci-*.yml, .trivyignore).
- Registro: Amazon ECR com um repositório `<svc>-service` por serviço, criado na camada base do Terraform; scan_on_push, AES256, image_tag_mutability MUTABLE por padrão, lifecycle que mantém 10 imagens e force_delete (terraform/modules/ecr/main.tf, terraform/variables.tf).
- Tags: `v1.0.0-<7 primeiros chars do GITHUB_SHA>` (prefixo copiado do exemplo do PDF) e `latest` só por conveniência. O deploy referencia apenas a tag com SHA, e o scan roda antes do push (_ci-*.yml, job image).
- AWS no CI: aws-actions/configure-aws-credentials@v4 com role-to-assume vars.AWS_ROLE_ARN, região vars.AWS_REGION (fallback us-east-2) e role-session-name gh-actions-<svc>; amazon-ecr-login@v2. Um passo bash valida o formato de ECR_REGISTRY e a coerência de conta/região com a role antes de publicar (_ci-*.yml).
- Trust OIDC: aud sts.amazonaws.com e `sub` StringEquals exato, com IDs numéricos imutáveis de owner/repo e ref:refs/heads/main. Política mínima: GetAuthorizationToken em * e push/pull só nos ARNs dos repositórios ECR. O provedor OIDC é criado ou reaproveitado conforme create_oidc_provider (terraform/modules/iam-ci/main.tf).
- Atualização do GitOps: instala o kustomize 5.4.3 standalone (o kubectl do runner não tem `kustomize edit`) e repete até 5 vezes: `git fetch` + `reset --hard origin/main`, `kustomize edit set image <svc>=<ECR>/<svc>:<tag>`, sai se `git diff --quiet` (idempotente), commit `chore(gitops): <svc> para <tag> [skip ci]` como github-actions[bot] e `git push origin HEAD:main`, com espera de 3s×tentativa (_ci-*.yml, job gitops).
- Anti-loop: push com GITHUB_TOKEN não dispara workflow, a mensagem leva [skip ci] e os paths dos serviços não incluem gitops/**. O CI nunca faz kubectl apply; quem aplica é o ArgoCD (_ci-*.yml, gitops-check.yml, terraform/k8s/argocd.tf).
- ArgoCD: helm_release do chart argo-cd 7.7.23 com global.image.tag v2.13.9 (correção da CVE-2025-55190); dex, applicationSet e notifications desligados; server.insecure; 1 réplica por componente; `timeout.reconciliation=30s` sem webhook, pois não há Ingress (terraform/k8s/argocd.tf, terraform/k8s/variables.tf).
- Application togglemaster (kubernetes_manifest): source = repositório, branch main, path gitops/overlays/prod; destino in-cluster, namespace togglemaster, project default. automated prune+selfHeal, CreateNamespace=true, RespectIgnoreDifferences=true, ignoreDifferences de /spec/replicas em evaluation e analytics, retry 5 (5s, fator 2, máx 3m) (terraform/k8s/argocd.tf).
- Application observability no padrão app of apps: aponta para gitops/observability, que gera 4 Applications filhas Helm multi-source (chart pinado + `$values` do repositório na main): kube-prometheus-stack 92.17.1 (ServerSideApply) e loki 7.5.0 na wave 0, otel-gateway 0.178.2 na wave 1 e otel-agent na wave 2. Todas com resources-finalizer, prune+selfHeal e retry (terraform/k8s/observability.tf, gitops/observability/applications/*.yaml).
- Kustomize. Base: namespace togglemaster; labels part-of/managed-by com includeSelectors false; imagens por nome lógico; configMapGenerator otel-config com sufixo de hash (pods reiniciam quando muda). Overlay prod: patches estratégicos irsa.yaml e endpoints.yaml, configMapGenerator merge com OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=prod e bloco images (gitops/base/kustomization.yaml, gitops/overlays/prod/kustomization.yaml).
- Requests/limits por container nos deployment.yaml da base, sem patch no overlay: auth 50m/64Mi→200m/128Mi; flag, targeting e analytics 100m/128Mi→300m/256Mi; evaluation 100m/64Mi→500m/128Mi; postgres-targeting 100m/128Mi→500m/512Mi com PVC gp3 de 5Gi. A observabilidade define os seus nos values (Prometheus 200m/512Mi, limite de 1536Mi; Loki 100m/256Mi, limite de 1Gi; otel-gateway 100m/256Mi, limite de 512Mi etc., sem limite de CPU) (gitops/base/*/deployment.yaml, gitops/observability/values/*.yaml).
- Probes: readiness e liveness com httpGet /health na porta do serviço (readiness em 10s nos serviços Go e 15s nos Python; liveness com delay de 30s e período de 30s; failureThreshold 3). O postgres usa exec pg_isready. Não há startupProbe (gitops/base/*/deployment.yaml, gitops/base/postgres-targeting/statefulset.yaml).
- HPA autoscaling/v2 só em evaluation e analytics: CPU 70% do request, min 1, max 2; depende do Metrics Server (gitops/base/{evaluation,analytics}-service/hpa.yaml).
- Segredos sem ESO: o Terraform (kubernetes_secret_v1) cria auth-service-secret, flag-service-secret, targeting-service-secret, postgres-targeting-secret, evaluation-service-secret, grafana-admin, newrelic-license e grafana-notificacoes. Os pods leem via secretKeyRef, o Grafana via existingSecret/envFromSecret e o Collector via extraEnvs. As chaves SaaS chegam por TF_VAR_*, e evaluation-service-secret tem lifecycle ignore_changes (terraform/k8s/secrets.tf, terraform/k8s/observability.tf, gitops/SECRETS-CONTRATO.md).
- Acesso dos pods à AWS por IRSA: a ServiceAccount na base não tem anotação, e o patch do overlay adiciona eks.amazonaws.com/role-arn. Uma role é produtora (SQS send) e a outra consumidora (SQS receive/delete + DynamoDB put). As URLs de SQS e Redis ficam em ConfigMap via patch, não em Secret (gitops/base/*/serviceaccount.yaml, gitops/overlays/prod/patches/*.yaml).
- GitOps Check, sem filtro de caminho (para varrer segredos em todo commit), em pull_request, push [main, dev] e dispatch. Instala Python 3.12, PyYAML 6.0.3 e kustomize 5.4.3 com SHA-256 conferido. validate.sh renderiza toda pasta com kustomization.yaml e roda check-grafana.py e os 13 casos de test-check-grafana.py; depois rodam test-restart.sh (11 cenários) e security-check.sh com `if: !cancelled()` (gitops-check.yml, scripts/gitops/validate.sh).
- Terraform Check em PR e push [main, dev] com paths terraform/** e no próprio arquivo, mais dispatch: setup-terraform@v3 com Terraform 1.16.0, `fmt -recursive -check`, `init -backend=false` + validate nas camadas terraform, terraform/cluster e terraform/k8s, e `terraform test` do iam-ci (10 casos), tudo sem credencial (terraform-check.yml).
- Integração em PR e push [main, dev] com paths-ignore de 00_COLAB_IA/**, docs/** e **.md, mais dispatch. Roda scripts/test-compose.sh com .env.example e docker-compose.integration.yaml (motoserver/moto 5.2.2 pinado por digest, emula SQS e DynamoDB) e depois scripts/integration/test-flow.py. Timeout de 20 min; logs em falha e `down -v` sempre (compose-integration.yml).
- Self-healing: repository_dispatch (types [self-healing]) vindo do contact point do Grafana, ou dispatch manual com choice dos 5 serviços. Usa role OIDC separada, só com eks:DescribeCluster; access entry STANDARD ligado ao grupo togglemaster-self-healing; RBAC restrito a patch nos 5 Deployments; actions pinadas por SHA; kubectl v1.34.13; concurrency `self-healing` sem cancelamento; o payload entra por env (anti-injeção), com allowlist e cooldown de 600s (self-healing.yml, scripts/self-healing/restart.sh, terraform/cluster/self-healing.tf, gitops/base/self-healing-rbac.yaml).
- Branches: trabalho humano e de agentes na dev, promoção por PR dev→main; o robô comita tags direto na main; depois de cada publicação a dev é sincronizada com `git merge --ff-only origin/main` (docs/CI-CD.md, 00_COLAB_IA/DECISOES.md F3-D-020 e F3-D-021).
- O .gitattributes força `*.sh text eol=lf`, para scripts editados no Windows rodarem no runner Linux (.gitattributes).

### O que reaproveitar na Fase 5

| Item | Como reaproveitar |
|---|---|
| Padrão chamador fino + reutilizável por stack (.github/workflows/*-service.yml + _ci-go.yml/_ci-python.yml) | Criar donation-service.yml chamando _ci-go.yml e ngo-service.yml e volunteer-service.yml chamando _ci-python.yml; trocar nomes, paths e grupo de concurrency. |
| Jobs build/lint/sast/sca/image-scan/image do _ci-go.yml | Usar no donation-service. Antes, gerar e versionar o go.sum (go mod tidy) e criar o Dockerfile multi-stage. Conferir a diretiva go 1.21 contra golangci-lint v2.13.2 e gosec com Go 1.25. Declarar permissions mínimas também nos jobs de verificação. |
| _ci-python.yml | Usar em ngo e volunteer. Alinhar PYTHON_VERSION com a imagem base escolhida, tornar os testes obrigatórios (REQ-OBR-08) em vez de 'se houver', fixar versões de bandit e pytest e corrigir os comentários desatualizados. |
| Job gitops (laço fetch/reset/kustomize edit/commit [skip ci]/push com backoff) | Copiar quase literal; muda só o caminho do overlay, se mudar. Com 3 serviços, o laço de 5 tentativas sobra. |
| Passos 'Validar destino AWS', OIDC e login/push no ECR | Copiar trocando apenas as mensagens que citam 'Fase 4' e o nome do projeto; manter as variables do repositório. |
| gitops-check.yml + scripts/gitops/validate.sh | Copiar o workflow e o validate.sh. Adaptar check-grafana.py e test-check-grafana.py aos novos dashboards: uid, títulos de regra e receivers usados nos casos. |
| scripts/security-check.sh e scripts/validate-all.sh | Remover a regra do ID de conta da Fase 2 e incluir padrões das chaves SaaS. Atualizar a lista de serviços, linguagens e camadas Terraform no validate-all. |
| terraform-check.yml | Apontar para os diretórios das camadas Terraform da Fase 5 e manter o terraform test do módulo OIDC. |
| compose-integration.yml + docker-compose.integration.yaml (Moto) + scripts/test-compose.sh | Reaproveitar o Moto para SQS (donation) e para o DynamoDB SolidaryTechVolunteers (volunteer), com bootstrap. Reescrever scripts/integration/test-flow.py para os endpoints da SolidaryTech. |
| Estrutura gitops/base/<svc> (deployment, service, configmap, serviceaccount, hpa) e overlays/prod (images, patches irsa/endpoints, merge do otel-config) | Recriar para 3 serviços nas portas 8081/8082/8083; os três já expõem /health para as probes. IRSA para donation (SQS) e volunteer (DynamoDB); avaliar HPA no donation, o hot path. Tirar AWS_REGION da base e passar para o overlay. |
| terraform/k8s/argocd.tf (helm_release + Application com prune/selfHeal/ignoreDifferences/retry, reconciliação de 30s) | Trocar repo URL, path, namespace e nomes; manter o override da imagem corrigida ou subir a versão do chart; manter o bootstrap em duas etapas documentado. |
| App of apps da observabilidade (terraform/k8s/observability.tf + gitops/observability/applications/*.yaml) | Copiar trocando o repoURL do `$values`; revisar versões dos charts e os Secrets SaaS. |
| terraform/modules/iam-ci (sub exato, policy ECR mínima, role do self-healing) + tests/trust.tftest.hcl | Atualizar repositório, IDs numéricos, project_name e ARN do cluster; manter os testes. |
| terraform/modules/ecr | Copiar passando a lista ngo/donation/volunteer; decidir MUTABLE ou IMMUTABLE. |
| terraform/k8s/secrets.tf + gitops/SECRETS-CONTRATO.md | Secrets com DATABASE_URL para ngo e donation; volunteer sem Secret (IRSA para o DynamoDB). Atualizar o contrato junto. |
| self-healing.yml + restart.sh + test-restart.sh + self-healing-rbac.yaml + terraform/cluster/self-healing.tf | Reduzir a allowlist e o resourceNames do RBAC para os 3 serviços e ajustar namespace, nome do cluster e variables. |
| .trivyignore (cabeçalho de política), .pylintrc, .gitattributes, SECURITY.md, docs/CI-CD.md | Copiar como modelo. Começar o .trivyignore sem exceções e incluir só CVEs justificados; reescrever a doc com os nomes novos. |

### Riscos e pegadinhas

- Não havia proteção de branch no plano usado, então um check vermelho não impedia o merge (00_COLAB_IA/LOG_DE_TRABALHO.md). Se a main for protegida, é preciso liberar o github-actions[bot] no ruleset, senão o job gitops falha depois de 5 tentativas.
- Cada merge gera um commit do robô por serviço na main (5 seguidos após o merge do PR #2 no histórico). A dev fica atrás e, sem `git merge --ff-only origin/main` antes de retomar, o próximo PR conflita no overlay.
- Um grupo de concurrency compartilhado entre os serviços cancelava execuções pendentes (main, 2026-09-09) e foi removido do job gitops. Um disparo manual também cancelou runs de push do mesmo grupo (2026-11-05).
- A primeira versão do retry usava `git pull --rebase` e deixou o repositório em 'unmerged files' (2026-09-09); foi trocada pelo reset e reaplicação.
- Versões de actions e ferramentas quebraram o CI: trivy-action@0.28.0 não existe ('Unable to resolve action'); golangci-lint v1.61 recusa go.mod mais novo; gosec v2.21.4 não compila. O upgrade de x/crypto para fechar um CVE subiu a diretiva go para 1.25.0 e exigiu Go 1.25 no job do gosec (comentários em _ci-go.yml).
- O gate CRITICAL com ignore-unfixed false bloqueou por CVEs sem correção da imagem base (perl-base no python:3.12-slim). A saída foram 3 exceções nominais no .trivyignore, cuja data de revisão (2026-10-15) venceu sem revisão. O alpine 3.20 sem suporte forçou trocar os runtimes Go para alpine 3.24.
- Os jobs build/lint/sast/sca não declaram permissions e herdam do chamador id-token: write e contents: write; rodam pip install e linters de terceiros com token de escrita.
- A pinagem é inconsistente: trivy-action e as actions do self-healing estão por SHA, as demais por tag (@v4, @v5, @v9, @v2). bandit e o pytest do job build não têm versão fixa, e o kustomize do job gitops é baixado sem checksum (só o GitOps Check confere o SHA-256).
- O filtro de caminho do GitHub avalia só os 300 primeiros arquivos do diff. No primeiro merge (785 arquivos) funcionou porque os workflows estavam no topo da lista (LOG_DE_TRABALHO.md).
- repository_dispatch só dispara workflows da branch padrão: self-healing.yml precisa estar na main antes do ensaio.
- No cluster novo, o kubernetes_manifest da Application falha já no plan (CRD inexistente); é preciso aplicar em duas etapas com -target=helm_release.argocd (terraform/k8s/argocd.tf).
- O selfHeal do ArgoCD brigava com o HPA por spec.replicas; resolvido com ignoreDifferences + RespectIgnoreDifferences=true.
- O chart argo-cd 7.7.x instala imagem com a CVE-2025-55190, por isso o override para v2.13.9. Sem webhook, o polling de 30s multiplica os clones do repo-server.
- Segredos fora do GitOps: se o nome ou a chave divergir entre o Terraform e o secretKeyRef, o pod fica em CreateContainerConfigError sem erro no ArgoCD. O state do Terraform guarda os segredos em texto puro, e a SERVICE_API_KEY, com dois donos (Terraform e seed manual), precisou de ignore_changes.
- ConfigMaps comuns não reiniciam os pods quando mudam; só o otel-config gerado tem sufixo de hash.
- Comentários desatualizados podem enganar outro agente: os deployments ainda citam ESO/externalsecret.yaml; o overlay chama de 'sentinela' valores já reais; _ci-python.yml diz que não há testes Python, mas existem services/*/tests.
- O overlay versionado tem o ID da conta AWS (newName do ECR, URL da SQS, ARNs IRSA) num repositório público. AWS_REGION us-east-2 está fixo nos ConfigMaps da base.
- O ECR é MUTABLE e recebe push de latest, então a imutabilidade da tag é só convenção. Mudar para IMMUTABLE quebra a reexecução do workflow no mesmo commit (terraform/variables.tf).
- O self-healing aplica `kubectl rollout restart`, um patch feito fora do Git. Na Fase 5 vale apresentá-lo como remediação, não como deploy, por causa do REQ-OBR-02.
- No repositório da Fase 5: services/donation-service não tem go.sum, e nenhum dos 3 serviços tem Dockerfile nem testes, então o CI copiado falha no build ou no teste até isso existir.
- As versões fixadas na Fase 5 são antigas (golangci/x/crypto v0.20.0, aws-sdk-go v1, Flask 2.2.2 sem Werkzeug fixado, gunicorn 20.1.0) e podem reprovar no gate CRITICAL ou no import. Confirmar com Trivy e pip localmente antes de ligar o gate.
- O sub OIDC usa IDs numéricos de owner/repo. Se o sub emitido para o novo repositório tiver outro formato, o assume role falha com AccessDenied; conferir antes do primeiro push na main.
- Não foram encontrados em gitops/: securityContext/runAsNonRoot, PodDisruptionBudget, NetworkPolicy, LimitRange/ResourceQuota e startupProbe.
- A integração em Compose custa de 4 a 5 minutos por execução; por isso o paths-ignore para documentação.

### Dependências externas

- Repositório GitHub com Actions habilitado e GITHUB_TOKEN autorizado a escrever (contents: write) na main; uma política da organização ou um ruleset pode bloquear.
- Repository Variables, não segredos: AWS_REGION, AWS_ROLE_ARN, ECR_REGISTRY, AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME (docs/CI-CD.md).
- IDs numéricos imutáveis do owner e do repositório GitHub, como variáveis Terraform da camada base, para montar o sub OIDC.
- Conta AWS com provedor OIDC token.actions.githubusercontent.com (criado ou reaproveitado), role do CI com push no ECR e role do self-healing com eks:DescribeCluster.
- Amazon ECR (um repositório por serviço) e EKS com authentication_mode API_AND_CONFIG_MAP para o access entry do self-healing.
- Bucket S3 de state do Terraform, privado, versionado e criptografado; o state contém segredos.
- Token fine-grained do GitHub para repository_dispatch (TF_VAR_github_dispatch_token), guardado no Secret grafana-notificacoes.
- Token fine-grained de leitura (Contents read-only) para o ArgoCD, só se o repositório for privado (TF_VAR_github_token).
- Credenciais SaaS por TF_VAR_*: license key do New Relic, integration key da Events API v2 do PagerDuty e webhook do Slack.
- Repositórios Helm: argo-helm, prometheus-community, grafana e open-telemetry.
- Actions de terceiros: actions/checkout, actions/setup-python, actions/setup-go, golangci/golangci-lint-action, aquasecurity/trivy-action, aws-actions/configure-aws-credentials, aws-actions/amazon-ecr-login, hashicorp/setup-terraform e azure/setup-kubectl.
- Downloads em tempo de CI: kustomize 5.4.3 (releases do GitHub), gosec via go install, golangci-lint, base de CVEs do Trivy, PyPI e proxy de módulos Go.
- Imagens públicas: postgres:16-alpine, motoserver/moto:5.2.2 (por digest) e as imagens base dos Dockerfiles.

### Passos que ficaram manuais na Fase 4 (a eliminar na Fase 5)

- Configurar as 5 repository variables com `gh variable set` a partir dos outputs do Terraform (00_COLAB_IA/02_TRABALHO/GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md, linhas 47-52).
- Preencher gitops/overlays/prod/patches/irsa.yaml e endpoints.yaml com os outputs do Terraform via `sed -i` e commitar na dev (mesmo guia, seção 5; commit 'chore(gitops): preenche endpoints e roles IRSA da conta').
- Rodar todos os terraform plan/apply na máquina local; o CI só faz fmt, validate e test. A camada k8s exige bootstrap em duas etapas (-target=helm_release.argocd, depois o apply completo).
- Carregar segredos SaaS e tokens do GitHub do .env local como TF_VAR_* no momento do apply.
- Aplicar os schemas dos RDS com `kubectl run psql-... --image=postgres:16-alpine -- psql ... < services/<svc>/db/init.sql` (GUIA_DEPLOY_E_GRAVACAO, linhas 174-175).
- Fazer o seed da SERVICE_API_KEY: POST /admin/keys, depois `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -` e rollout restart (GUIA_DEPLOY_E_GRAVACAO, linha 183; 00_COLAB_IA/DOSSIE_CONTEXTO.md).
- Criar o gerador de tráfego com `kubectl run trafego` e injetar a falha por `kubectl exec`/`kubectl run falha` na demo (GUIA_DEPLOY_E_GRAVACAO, linhas 212 e 331; docs/gravacao/COMANDOS.md).
- Acessar ArgoCD, Grafana e evaluation por `kubectl port-forward` (docs/gravacao/COMANDOS.md).
- Sincronizar a dev com a main depois dos commits do robô (`git merge --ff-only origin/main`).
- Decidir o merge do PR dev→main conferindo os checks a olho, já que não havia proteção de branch.
- Revalidar as exceções do .trivyignore com `trivy image` ao trocar a imagem base ou antes da entrega.
- Usar o disparo manual do self-healing (workflow_dispatch) só para diagnóstico; ele não prova a cadeia automática.

### Dúvidas levantadas pela leitura (histórico)

- Qual é o repositório GitHub definitivo da Fase 5 (organização/nome) e ele será público ou privado? Isso define o sub OIDC, se o ArgoCD precisa de token de leitura e se há proteção de branch disponível.
- Mantemos o modelo da Fase 4 (dev → PR → main, robô comitando a tag direto na main com [skip ci], sem proteção de branch) ou vocês querem ruleset/proteção na main liberando o github-actions[bot]?
- Quando o Trivy CRITICAL reprovar, podemos atualizar as versões das dependências do código do coordenador (go.mod e requirements.txt)? Ou preferem manter as versões originais e registrar exceções nominais no .trivyignore?
- Que nível de teste vale no pipeline (Q-20 do mapa)? Testes unitários mínimos escritos por nós mais integração em Compose com Moto, como na Fase 4, é suficiente?
- Qual região AWS vale para a Fase 5? A Fase 4 usou us-east-2 (fallback do CI), e o README da Fase 5 usa us-east-1 nos exemplos.
- Mantemos a convenção de tag da Fase 4 (v1.0.0-<sha7> + latest) ou preferem outra (por exemplo, só o SHA)?

<a id="3-obs"></a>
## 3. Observabilidade e resposta a incidentes

Os cinco serviços usam SDKs OpenTelemetry (Go e Python), propagação só W3C TraceContext e /health excluído. Eles enviam apenas traces por OTLP/HTTP protobuf ao Collector central `otel-gateway` (Deployment, 1 réplica), configurado pelo ConfigMap gerado `otel-config`, e escrevem logs JSON no stdout com trace_id/span_id. O Collector `otel-agent` (DaemonSet) lê /var/log/pods em cada nó (preset logsCollection, que inclui os logs do próprio Collector), enriquece com k8s_attributes e envia por OTLP/gRPC ao gateway, que repassa ao Loki 3.6.11 (SingleBinary) pelo endpoint OTLP /otlp. No gateway, os traces passam por memory_limiter → filter/health → transform/sanitize (lista permitida de atributos) → k8s_attributes → batch e saem para o New Relic (otlp.nr-data.net, região US, header api-key vindo do Secret newrelic-license) e para o conector span_metrics. O span_metrics gera traces_span_metrics_calls_total e traces_span_metrics_duration_milliseconds_bucket (flush 15 s, expiração 5 min) e os envia ao receptor OTLP nativo do Prometheus; as métricas de infraestrutura vêm do scrape padrão do kube-prometheus-stack 92.17.1 (node-exporter, kubelet/cAdvisor). Tudo é GitOps: o Terraform cria o namespace, os Secrets e a Application `observability` (app of apps), que sincroniza 4 Applications Helm multi-source com versões fixadas e values versionados, em sync waves 0/1/2. O Grafana 13.3.0 é provisionado inteiramente como código: dashboard e alerting (templates, contact points, policies e regra) vão em ConfigMaps lidos pelos sidecars, com Alertmanager desligado e datasources Prometheus (uid prometheus) e Loki (uid loki). Existe uma única regra, FlagService5xxAlto: proporção de spans SERVER com STATUS_CODE_ERROR do flag-service acima de 10% por 1 minuto, avaliada a cada 30 s, com noDataState OK. Em Firing, o Grafana dispara em paralelo PagerDuty (Events API V2, abre e resolve o incidente), Slack (Incoming Webhook com mensagem detalhada) e, pela rota selfheal=true + alertname, um webhook repository_dispatch na API do GitHub; além disso, o app do PagerDuty publica seu cartão no mesmo canal do Slack. O workflow self-healing.yml assume por OIDC uma role que só tem eks:DescribeCluster e entra no cluster por access entry com RBAC que só permite patch nos 5 Deployments. Ele roda restart.sh: allowlist, cooldown de 600 s, rollout restart e rollout status. Nos ensaios locais (2026-10-27) saiu um trace de 19 spans com os 5 serviços, PostgreSQL, Redis, SQS produtor→consumidor e DynamoDB, com logs correlacionados e sanitização provada; no EKS (2026-11-09) o New Relic mostrou um trace de 19 spans/56,63 ms, e a cadeia automática foi de Firing 18:59:20 UTC a HTTP 200 às 19:00:19 e Resolved às 19:01:30 (run em 43 s, incidente PagerDuty #4). Na gravação de 2026-11-11 (UTC-03), a falha foi ativada às 00:58:48, houve Firing às 01:00:50, dispatch às 01:00:53, restart às 01:01:09, HTTP 200 às 01:01:38 e Resolved às 01:03:00, com 159 respostas 503; o ambiente AWS foi destruído em 2026-11-12. Para a Fase 5, a stack é quase toda reaproveitável, mas o nome 'togglemaster' e o flag-service estão fixados em muitos arquivos, e os 3 serviços novos não têm instrumentação, chamadas entre si nem consumidor da fila SQS.

### Arquivos-chave

| Caminho | Papel |
|---|---|
| `observability/README.md` | Documento principal da observabilidade: laboratório local, exportação New Relic, topologia no EKS, tabela de charts e versões, runbook do FlagService5xxAlto, evidência integrada e validações locais |
| `observability/otel-collector-local.yaml` | Collector do laboratório local: OTLP 4317/4318, memory_limiter, filter/health, transform/sanitize, batch e exporter de arquivo traces.jsonl |
| `observability/otel-collector-newrelic.yaml` | Segundo --config do Collector local que acrescenta o exporter otlp_http/newrelic |
| `docker-compose.otel.yaml` | Sobreposição Compose com Collector 0.163.2 fixado por digest e variáveis OTEL_* e OTEL_SERVICE_NAME por serviço |
| `docker-compose.newrelic.yaml` | Sobreposição que monta o exporter New Relic e exige NEW_RELIC_LICENSE_KEY do .env local |
| `docker-compose.integration.yaml` | Moto 5.2.2 (SQS/DynamoDB) e bootstrap para testes sem AWS |
| `scripts/test-observability.sh` | Ensaio local completo: valida a config do Collector, sobe o lab e roda test-flow.py e test-traces.py |
| `scripts/test-observability-newrelic.sh` | Mesmo ensaio com exportação ao New Relic e busca de erros de exportação nos logs do Collector |
| `scripts/integration/test-traces.py` | Prova de trace distribuído (5 serviços, produtor/consumidor SQS, spans PostgreSQL), logs correlacionados, sonda de privacidade e exclusão do /health; grava resultado-traces.json |
| `scripts/integration/test-flow.py` | Regressão funcional HTTP/bancos/Redis/fluxo assíncrono usada antes da prova de traces |
| `gitops/observability/kustomization.yaml` | Pasta da Application mãe: lista as 4 Applications e gera os ConfigMaps grafana-dashboard-togglemaster e grafana-alerting-togglemaster |
| `gitops/observability/applications/kube-prometheus-stack.yaml` | Application do chart kube-prometheus-stack 92.17.1 (wave 0, ServerSideApply, multi-source com $values) |
| `gitops/observability/applications/loki.yaml` | Application do chart loki 7.5.0 (wave 0) |
| `gitops/observability/applications/otel-gateway.yaml` | Application do chart opentelemetry-collector 0.178.2 no papel gateway (wave 1) |
| `gitops/observability/applications/otel-agent.yaml` | Application do chart opentelemetry-collector 0.178.2 no papel agente DaemonSet (wave 2) |
| `gitops/observability/values/otel-gateway.yaml` | Pipelines do gateway: sanitização, k8s_attributes, span_metrics e exporters New Relic, Prometheus (OTLP) e Loki (OTLP) |
| `gitops/observability/values/otel-agent.yaml` | DaemonSet de coleta de logs de contêiner (file_log) com envio OTLP/gRPC ao gateway |
| `gitops/observability/values/kube-prometheus-stack.yaml` | Prometheus (receptor OTLP, retenção, PVC gp3), Grafana (segredos por env, sidecars, datasources) e componentes desligados |
| `gitops/observability/values/loki.yaml` | Loki SingleBinary com filesystem, schema v13, structured metadata e PVC gp3 |
| `gitops/observability/grafana/alerting/rules.yaml` | Regra FlagService5xxAlto (PromQL sobre span metrics, threshold, labels de roteamento, annotations e runbook) |
| `gitops/observability/grafana/alerting/policies.yaml` | Árvore de notificação: incidente para qualquer alerta e self-healing só para selfheal=true + alertname |
| `gitops/observability/grafana/alerting/contactpoints.yaml` | Contact points togglemaster-incidente (PagerDuty + Slack) e togglemaster-self-healing (webhook repository_dispatch) |
| `gitops/observability/grafana/alerting/templates.yaml` | Templates de título, texto do Slack e corpo JSON do repository_dispatch |
| `gitops/observability/grafana/dashboards/togglemaster-overview.json` | Dashboard customizado: 5xx, RPS, p95, CPU/memória de nós e pods e logs do Loki |
| `gitops/base/kustomization.yaml` | configMapGenerator otel-config (endpoint do gateway, protocolo, amostragem) comum aos serviços |
| `gitops/overlays/prod/kustomization.yaml` | Merge do otel-config com OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=prod |
| `gitops/base/self-healing-rbac.yaml` | Role/RoleBinding: leitura de deployments/replicasets/pods e patch só nos 5 Deployments, para o grupo togglemaster-self-healing |
| `.github/workflows/self-healing.yml` | Workflow acionado por repository_dispatch (e manual): OIDC, kubeconfig do EKS, restart.sh e listagem dos pods |
| `scripts/self-healing/restart.sh` | Reinício seguro: só status firing, allowlist, cooldown pela anotação restartedAt, rollout restart/status e result em GITHUB_OUTPUT |
| `scripts/self-healing/test-restart.sh` | 11 cenários do restart.sh com kubectl falso, executados no GitOps Check |
| `terraform/k8s/observability.tf` | Namespace observability, Secrets grafana-admin, newrelic-license e grafana-notificacoes e a Application mãe observability |
| `terraform/k8s/variables.tf` | Variáveis sensíveis da observabilidade com validações de formato (New Relic, PagerDuty, Slack e token de dispatch) |
| `terraform/cluster/self-healing.tf` | Access entry do EKS que mapeia a role de self-healing para o grupo Kubernetes togglemaster-self-healing |
| `terraform/modules/iam-ci/main.tf` | Role IAM de self-healing (trust OIDC do GitHub, só eks:DescribeCluster no cluster) |
| `scripts/gitops/check-grafana.py` | Verificador estático de dashboards e alerting (JSON/YAML, uids, painéis, datasources, receivers, matcher de alertname, cifrão duplicado) |
| `scripts/gitops/test-check-grafana.py` | Testes de mutação do verificador do Grafana |
| `.github/workflows/gitops-check.yml` | CI que roda kustomize, check-grafana, test-restart e varredura de segredos |
| `services/flag-service/telemetry.py` | Bootstrap Python: SDK OTLP/HTTP, FlaskInstrumentor sem /health, psycopg2/requests e logs JSON com trace_id |
| `services/evaluation-service/telemetry.go` | Bootstrap Go: otlptracehttp, otelhttp com filtro de /health, logger slog JSON correlacionado e spans de dependência |
| `services/evaluation-service/sqs.go` | Produtor SQS com span PRODUCER e traceparent/tracestate em MessageAttributes |
| `services/analytics-service/app.py` | Consumidor SQS com extração W3C, span CONSUMER e spans manuais de DynamoDB PutItem e DeleteMessage |
| `services/flag-service/app.py` | Falha controlada /admin/fault autenticada (503 nas rotas /flags, /health saudável, estado só em memória) |
| `docs/ARQUITETURA.md` | Arquitetura: caminho dos três sinais e cadeia alerta → incidente → recuperação, com horários do ensaio |
| `docs/CONCEITOS_OBSERVABILIDADE.md` | Conceitos (métricas, logs e traces; agente e gateway; DaemonSet e Deployment) aplicados ao projeto |
| `docs/evidencias/README.md` | Prints datados de 2026-11-09 e linha do tempo da gravação de 2026-11-11 |
| `gitops/SECRETS-CONTRATO.md` | Contrato de nomes e chaves dos Secrets da observabilidade |
| `docs/gravacao/COMANDOS.md` | Comandos operacionais da demonstração (túneis, trace sem cache, Loki, falha controlada) |
| `00_COLAB_IA/02_TRABALHO/GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md` | Passo a passo real de deploy e gravação, com os passos manuais (Variables, TF_VAR, psql, chave, pod trafego, port-forward, destroy) |
| `00_COLAB_IA/02_TRABALHO/PASSO2_CONTAS_SAAS_2026-11-01_v01.md` | Configuração manual das contas New Relic, PagerDuty e Slack e da integração PagerDuty↔Slack |

### Decisões técnicas da Fase 4

- Collector em dois papéis com o mesmo chart opentelemetry-collector 0.178.2 (otel/opentelemetry-collector-contrib 0.163.2, imagem fixada por digest, command otelcol-contrib): gateway com mode deployment, replicaCount 1 e fullnameOverride otel-gateway; agente com mode daemonset e fullnameOverride otel-agent (gitops/observability/values/otel-gateway.yaml, gitops/observability/values/otel-agent.yaml)
- Nomes atuais dos componentes do Collector (otlp_http, otlp_grpc, span_metrics, k8s_attributes, file_log); os antigos (otlphttp, spanmetrics) são aliases obsoletos desde a v0.144.0 (gitops/observability/values/otel-gateway.yaml; 00_COLAB_IA/02_TRABALHO/PASSO2_CONTAS_SAAS_2026-11-01_v01.md)
- Serviços exportam só traces: OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.observability.svc.cluster.local:4318, OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf, OTEL_TRACES_SAMPLER=parentbased_always_on e OTEL_SDK_DISABLED=false, por configMapGenerator otel-config com hash para reiniciar pods quando muda (gitops/base/kustomization.yaml); OTEL_SERVICE_NAME no ConfigMap de cada serviço (gitops/base/*/configmap.yaml); deployment.environment.name=prod por merge no overlay (gitops/overlays/prod/kustomization.yaml)
- Instrumentação: Python opentelemetry-api/sdk/exporter-otlp-proto-http 1.45.1 e instrumentations flask/requests/psycopg2 0.66b1; Go otel 1.46.0, otelhttp 0.71.0 e go 1.25.0; propagador só W3C TraceContext, sem baggage; /health excluído na instrumentação; logs JSON com trace_id/span_id; service.namespace=togglemaster fixado no código; Gunicorn sem --preload (services/flag-service/requirements.txt, services/evaluation-service/go.mod, services/*/telemetry.py, services/*/telemetry.go)
- Contexto assíncrono: o produtor SQS cria um span PRODUCER e injeta traceparent/tracestate em MessageAttributes; o consumidor extrai o contexto e cria o span CONSUMER mais os spans manuais dynamodb.PutItem e sqs.DeleteMessage; o corpo de negócio não recebe campos de tracing (services/evaluation-service/sqs.go, services/analytics-service/app.py)
- Gateway: receivers só OTLP (jaeger, zipkin e prometheus nulos e portas desligadas); processors memory_limiter e batch padrão do chart (80%/25% do limite), filter/health (http.route, url.path e http.target iguais a /health), transform/sanitize com keep_keys em resource/span/spanevent e status.message zerado; k8s_attributes DEPOIS da sanitização, via preset kubernetesAttributes (gitops/observability/values/otel-gateway.yaml)
- Pipelines do gateway: traces [otlp] → [memory_limiter, filter/health, transform/sanitize, k8s_attributes, batch] → [otlp_http/newrelic, span_metrics]; metrics [span_metrics] → [memory_limiter, batch] → [otlp_http/prometheus]; logs [otlp] → [memory_limiter, batch] → [otlp_http/loki]; exporter debug nulo para não criar ciclo de logs (gitops/observability/values/otel-gateway.yaml)
- Conector span_metrics: namespace traces.span.metrics, metrics_flush_interval 15s (alerta mais rápido no vídeo), metrics_expiration 5m, buckets explícitos 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2500ms e 5s; dimensões padrão service.name, span.name, span.kind e status.code; no Prometheus viram traces_span_metrics_calls_total e traces_span_metrics_duration_milliseconds_bucket (gitops/observability/values/otel-gateway.yaml, gitops/observability/values/kube-prometheus-stack.yaml)
- Envio ao New Relic: só traces, exporter otlp_http/newrelic com endpoint https://otlp.nr-data.net (conta US), header api-key de ${env:NEW_RELIC_LICENSE_KEY} (Secret newrelic-license via extraEnvs) e compressão gzip; no local, o mesmo exporter entra como segundo --config (gitops/observability/values/otel-gateway.yaml, observability/otel-collector-newrelic.yaml, docker-compose.newrelic.yaml)
- Agente: preset logsCollection (file_log em /var/log/pods/*/*/*.log com operador container, includeCollectorLogs true e storeCheckpoints true, o que faz o contêiner rodar como root) e preset kubernetesAttributes; sem portas de entrada; pipeline logs [file_log] → [memory_limiter, k8s_attributes, batch] → [otlp_grpc → otel-gateway.observability.svc.cluster.local:4317, tls insecure]; requests 50m/128Mi e limit 256Mi (gitops/observability/values/otel-agent.yaml)
- kube-prometheus-stack 92.17.1 (Prometheus 3.15.1; subchart grafana 14.3.1 com Grafana 13.3.0-distroless, versão escolhida pela correção de CVE): fullnameOverride kps; enableOTLPReceiver true; retenção 2d/4GiB; PVC gp3 de 5Gi; Alertmanager desligado; kubeControllerManager, kubeScheduler, kubeEtcd e kubeProxy desligados por ser EKS; defaultRules sem os grupos desses componentes; Prometheus com requests 200m/512Mi e limit 1536Mi (gitops/observability/values/kube-prometheus-stack.yaml)
- Loki chart 7.5.0 (imagem 3.6.11): deploymentMode SingleBinary, auth_enabled false, storage filesystem, schema v13/tsdb, allow_structured_metadata true (trace_id e span_id viram metadados), PVC gp3 de 5Gi, gateway/minio/caches/canary/test desligados; os logs chegam por OTLP em http://loki.observability.svc.cluster.local:3100/otlp, e service.name e k8s.namespace.name viram os labels service_name e k8s_namespace_name (gitops/observability/values/loki.yaml)
- App of apps: o Terraform cria a Application observability (path gitops/observability, automated prune/selfHeal, retry); as 4 filhas usam multi-source (chart oficial + $values do repositório, branch main), sync-wave 0 (kps, loki), 1 (otel-gateway) e 2 (otel-agent), finalizer resources-finalizer e ServerSideApply só no kps por causa do tamanho dos CRDs (terraform/k8s/observability.tf, gitops/observability/applications/*.yaml)
- Grafana como código: dashboards e alerting em ConfigMaps com labels grafana_dashboard: "1" e grafana_alert: "1" lidos pelos sidecars, com disableNameSuffixHash true; datasource Prometheus padrão com uid prometheus; Loki em additionalDataSources com uid loki; datasource do Alertmanager desligada; persistence desligada (estado reconstruído do Git); admin por existingSecret grafana-admin; segredos dos contact points por envFromSecret grafana-notificacoes; root_url http://localhost:3000 por não haver Ingress (gitops/observability/kustomization.yaml, gitops/observability/values/kube-prometheus-stack.yaml)
- Regra FlagService5xxAlto (uid flag-service-5xx, pasta ToggleMaster, grupo togglemaster-flag-service, interval 30s, for 1m): consulta instantânea A = (sum(rate(traces_span_metrics_calls_total{service_name="flag-service", span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[1m])) or vector(0)) / sum(rate(traces_span_metrics_calls_total{service_name="flag-service", span_kind="SPAN_KIND_SERVER"}[1m])), relativeTimeRange 300s; condição C threshold gt 0.1; noDataState OK; execErrState Error; labels severity=critical, service=flag-service e selfheal="true"; dashboardUid togglemaster-overview e panelId 2 (gitops/observability/grafana/alerting/rules.yaml)
- Consultas do dashboard 'ToggleMaster - Visao geral' (uid togglemaster-overview, refresh 30s, últimos 30 min): taxa de 5xx por serviço = (sum by (service_name) (rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[1m])) or (0 * sum by (service_name) (rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[1m])))) / sum by (service_name) (rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[1m])); RPS = sum by (service_name) (rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[1m])); p95 = histogram_quantile(0.95, sum by (le, service_name) (rate(traces_span_metrics_duration_milliseconds_bucket{span_kind="SPAN_KIND_SERVER"}[5m]))); CPU de nó = (1 - sum by (instance) (rate(node_cpu_seconds_total{mode=~"idle|iowait|steal"}[5m])) / sum by (instance) (rate(node_cpu_seconds_total[5m]))) * on (instance) group_left (nodename) node_uname_info; memória de nó = (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) com o mesmo join; CPU de pod = sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="togglemaster", container!="", container!="POD"}[5m])); memória de pod = sum by (pod) (container_memory_working_set_bytes{...}); logs = {k8s_namespace_name="togglemaster"} (gitops/observability/grafana/dashboards/togglemaster-overview.json)
- Roteamento: a política raiz substitui a padrão, com receiver togglemaster-incidente, group_by [grafana_folder, alertname, service], group_wait 10s, group_interval 1m e repeat_interval 4h; a rota severity=critical vai para togglemaster-incidente com continue true; a rota selfheal=true E alertname=FlagService5xxAlto vai para togglemaster-self-healing com group_wait 0s e repeat_interval 1h (gitops/observability/grafana/alerting/policies.yaml)
- Contact points: PagerDuty (integrationKey $PAGERDUTY_INTEGRATION_KEY, severity critical, class http-5xx, component vindo do label service, group togglemaster, source grafana-togglemaster); Slack (url $SLACK_WEBHOOK_URL e templates de título/texto); webhook do GitHub (POST /repos/<dono>/<repo>/dispatches, authorization_scheme Bearer com authorization_credentials $GITHUB_DISPATCH_TOKEN, headers Accept e X-GitHub-Api-Version 2026-03-10, payload template {"event_type":"self-healing","client_payload":{service, alertname, status}} e disableResolveMessage true) (gitops/observability/grafana/alerting/contactpoints.yaml, gitops/observability/grafana/alerting/templates.yaml)
- Comunicação no Slack por dois caminhos: mensagem detalhada do Grafana pelo Incoming Webhook e cartão do incidente publicado pelo app do PagerDuty conectado ao canal #incidentes-tech-challenge via /pd connect (docs/ARQUITETURA.md, 00_COLAB_IA/02_TRABALHO/PASSO2_CONTAS_SAAS_2026-11-01_v01.md)
- Self-healing: o workflow recebe repository_dispatch do tipo self-healing ou workflow_dispatch com choice dos 5 serviços; permissions contents read e id-token write; concurrency self-healing sem cancelamento; o nome do serviço entra por env (nunca interpolado no run); actions fixadas por SHA; kubectl v1.34.13 por compatibilidade com o EKS 1.34; COOLDOWN_SECONDS 600; NAMESPACE togglemaster (.github/workflows/self-healing.yml)
- restart.sh: só age com ALERT_STATUS=firing; allowlist por igualdade (nome recusado sai com código 2, sem repetir o valor no log); cooldown lido da anotação kubectl.kubernetes.io/restartedAt; rollout restart e rollout status com timeout de 180s; result restarted, cooldown, refused, ignored ou failed em GITHUB_OUTPUT e resumo em GITHUB_STEP_SUMMARY (scripts/self-healing/restart.sh)
- Identidade do self-healing em camadas: role IAM ${project_name}-self-healing com a mesma trust OIDC do CI (subject da main) e só eks:DescribeCluster no ARN do cluster; access entry STANDARD mapeando para o grupo togglemaster-self-healing (cluster com authentication_mode API_AND_CONFIG_MAP); Role no namespace com get/list/watch em deployments/replicasets/pods e patch só nos 5 Deployments (terraform/modules/iam-ci/main.tf, terraform/cluster/self-healing.tf, gitops/base/self-healing-rbac.yaml)
- Segredos fora do Git: TF_VAR_new_relic_license_key, TF_VAR_pagerduty_integration_key, TF_VAR_slack_webhook_url e TF_VAR_github_dispatch_token (sem default, sensitive, lidos do .env local) viram os Secrets newrelic-license, grafana-notificacoes e grafana-admin (random_password de 24 caracteres); validações: chave New Relic de 40 caracteres, PagerDuty de 32 alfanuméricos que não pareça número, Slack começando com https://hooks.slack.com/services/, token github_pat_ ou ghp_ (terraform/k8s/observability.tf, terraform/k8s/variables.tf, terraform/k8s/terraform.tfvars.example)
- Região AWS us-east-2 nos exemplos, EKS 1.34 com 2 nós m7i-flex.large; a stack foi dimensionada para dividir esses 2 nós com as aplicações e o ArgoCD (terraform/k8s/terraform.tfvars.example, docs/ARQUITETURA.md, gitops/observability/values/kube-prometheus-stack.yaml)
- Validação no CI sem cluster: GitOps Check instala kustomize 5.4.3 com checksum e roda scripts/gitops/validate.sh (render de toda pasta com kustomization, check-grafana.py e seus testes), test-restart.sh (11 cenários) e security-check.sh (.github/workflows/gitops-check.yml, scripts/gitops/validate.sh)
- Laboratório local sem AWS: Moto 5.2.2 fixado por digest no lugar de SQS/DynamoDB, Collector com limite de 256M, portas publicadas só em 127.0.0.1 e traces gravados em JSONL para asserção automática (docker-compose.integration.yaml, docker-compose.otel.yaml, observability/otel-collector-local.yaml)
- Falha controlada para a demonstração: POST /admin/fault autenticado liga um estado em memória que devolve 503 em /flags e /flags/*, mantendo /health saudável; o flag-service tem 1 réplica e 1 worker Gunicorn, então o rollout restart resolve (services/flag-service/app.py, services/flag-service/tests/test_fault.py)

### O que reaproveitar na Fase 5

| Item | Como reaproveitar |
|---|---|
| Values do Collector gateway (gitops/observability/values/otel-gateway.yaml) | Copiar quase integralmente: pipelines, filter/health, sanitização por lista permitida, k8s_attributes, span_metrics e exporters já são genéricos (label service_name). Revisar só os comentários de '5 servicos' e, se o SLO de latência do donation-service usar um limiar fora dos buckets atuais (5ms a 5s), acrescentá-lo em histogram.explicit.buckets. |
| Values do agente DaemonSet (otel-agent.yaml) e do Loki (loki.yaml) | Copiar sem mudança funcional. Manter debug: null no agente e no gateway enquanto includeCollectorLogs=true, e manter allow_structured_metadata para trace_id/span_id. |
| Applications Argo CD e kustomization da observabilidade (gitops/observability/applications/*.yaml, gitops/observability/kustomization.yaml) | Trocar o repoURL da fonte $values (hoje fixado no repositório tech-challenge-04) pelo repositório da Fase 5 e renomear os ConfigMaps grafana-dashboard-togglemaster e grafana-alerting-togglemaster. Incluir o novo dashboard SRE no configMapGenerator. Manter versões fixadas, sync waves e ServerSideApply no kps. |
| Values do kube-prometheus-stack (gitops/observability/values/kube-prometheus-stack.yaml) | Ajustar retenção e disco: 2d/4GiB em PVC de 5Gi não cobrem a janela do SLO/error budget. Avaliar também recording rules. Redimensionar para o novo cluster e manter Alertmanager desligado, datasources por uid, admin por existingSecret e envFromSecret. |
| Dashboard togglemaster-overview.json | Trocar uid, título e tags; mudar o painel 1 (stat do flag-service) para donation-service; trocar namespace="togglemaster" nos painéis 5 e 6 e {k8s_namespace_name="togglemaster"} no painel 7 pelo novo namespace. Os painéis 2, 3, 4, 8 e 9 servem sem mudança. O dashboard SRE (SLIs, SLOs, error budget) exigido na Fase 5 é um arquivo novo. |
| Regra de alerta (gitops/observability/grafana/alerting/rules.yaml) | Adaptar a FlagService5xxAlto para o donation-service: service_name="donation-service" na expr e novo título, uid, grupo, pasta, labels service/selfheal, dashboardUid/panelId, summary/description e runbook_url (o nome final é decisão do time). Manter $values com cifrão simples nas annotations. As regras de SLO/burn rate entram como regras adicionais. |
| Policies, contact points e templates do Grafana | Renomear togglemaster-* (contact points, uids dos receivers, templates, group e source do PagerDuty) e atualizar o matcher alertname da rota de self-healing para o novo título da regra. Trocar a URL do dispatch para o repositório da Fase 5. Manter disableResolveMessage, authorization_scheme/credentials, payload template e a rota com continue. |
| Self-healing (scripts/self-healing/restart.sh, scripts/self-healing/test-restart.sh, .github/workflows/self-healing.yml, gitops/base/self-healing-rbac.yaml) | Trocar a ALLOWLIST, as options do workflow_dispatch, o NAMESPACE, os resourceNames do Role e os nomes usados nos testes (flag-service, evaluation-service, postgres-targeting). Garantir o label app=<serviço> nos novos Deployments, porque o workflow lista pods por ele, e fixar um kubectl compatível com a versão do novo EKS. A lógica de allowlist, cooldown e rollout status é reaproveitada. |
| Identidade AWS/Kubernetes do self-healing (terraform/modules/iam-ci/main.tf, terraform/cluster/self-healing.tf) | Copiar a role OIDC que só tem eks:DescribeCluster e o access entry STANDARD. Renomear o grupo Kubernetes (hoje togglemaster-self-healing) com o mesmo valor no RoleBinding e cadastrar AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME como Variables do novo repositório. |
| Segredos e Application mãe da observabilidade (terraform/k8s/observability.tf, terraform/k8s/variables.tf) | Copiar o contrato newrelic-license / grafana-admin / grafana-notificacoes, o random_password e as validações de formato. Ajustar o label app.kubernetes.io/part-of e o gitops_repo_url. |
| Bootstrap de telemetria (services/flag-service/telemetry.py, services/evaluation-service/telemetry.go) | Copiar para ngo-service e volunteer-service (Python) e donation-service (Go), trocando service.namespace 'togglemaster'. Acrescentar as dependências OTel fixadas (Python 1.45.1/0.66b1; Go otel 1.46.0/otelhttp 0.71.0) e os pins Werkzeug<3/setuptools<81 usados com Flask 2.2.2. No donation-service, subir o 'go 1.21' (a Fase 4 usa go 1.25.0 e r.Pattern). No ngo-service, mover cursor_factory=RealDictCursor para o pool. Trocar os logs de texto por JSON correlacionado. |
| Produtor SQS com contexto W3C (services/evaluation-service/sqs.go) | Reaplicar no sendNotificationEvent do donation-service: span PRODUCER, traceparent/tracestate em MessageAttributes, context.WithoutCancel com timeout de 5 s e WaitGroup para drenar no shutdown. Hoje ele roda em goroutine sem contexto. Trocar também QueryRow/Query por QueryRowContext/QueryContext com spans de dependência. |
| Spans manuais de DynamoDB (traced_operation em services/analytics-service/app.py) | Reaplicar no volunteer-service para put_item e scan, com db.system.name aws.dynamodb e db.operation.name, sem payload nem mensagem de exceção. |
| ConfigMap otel-config gerado com hash e merge de OTEL_RESOURCE_ATTRIBUTES no overlay (gitops/base/kustomization.yaml, gitops/overlays/prod/kustomization.yaml) | Copiar como está, trocando só o OTEL_SERVICE_NAME de cada serviço (ngo-service, donation-service, volunteer-service) e o namespace do endpoint, se mudar. |
| Verificador do Grafana no CI (scripts/gitops/check-grafana.py, scripts/gitops/test-check-grafana.py, scripts/gitops/validate.sh, .github/workflows/gitops-check.yml) | Copiar o verificador. No teste, atualizar as constantes DASHBOARD/RULES/POLICIES e os trechos literais procurados (title: FlagService5xxAlto, summary: 'flag-service, receiver: togglemaster-self-healing); sem isso os casos falham de propósito. |
| Laboratório local de traces (observability/otel-collector-local.yaml, docker-compose.otel.yaml, docker-compose.newrelic.yaml, scripts/test-observability*.sh) | Os arquivos do Collector local e o overlay New Relic podem ser copiados. Adaptar as âncoras por serviço, as portas 8081–8083 e o Moto para SQS/DynamoDB. |
| Prova automatizada de traces (scripts/integration/test-traces.py) | Reescrever as asserções de topologia: a Fase 4 exige 5 serviços no mesmo trace e o par produtor/consumidor SQS, mas o código da Fase 5 não tem chamadas entre serviços nem consumidor da fila. Reaproveitar a sonda de privacidade, a exclusão do /health e a checagem de logs JSON correlacionados. |
| Falha controlada /admin/fault (services/flag-service/app.py, services/flag-service/tests/test_fault.py) | Se aprovado, reaplicar no donation-service: estado só em memória, /health saudável e rollout restart resolvendo. Falta definir a proteção do endpoint, pois os serviços da Fase 5 não têm autenticação. |
| Linha do tempo medida para MTTR (docs/evidencias/README.md, docs/relatorio/dados-entrega.json) | Reaproveitar a coleta de horários (Loki, log do run do Actions e Slack) para a seção de MTTR da Fase 5. Calculado a partir dos horários de 2026-11-11: falha → Firing 2 min 02 s; Firing → dispatch 3 s; dispatch → restart 16 s; restart → rollout concluído 22 s; Firing → HTTP 200 48 s; falha → HTTP 200 2 min 50 s; falha → Resolved 4 min 12 s. Em 2026-11-09: Firing → HTTP 200 59 s e Firing → Resolved 2 min 10 s. |
| Documentação (observability/README.md, docs/ARQUITETURA.md seções 4 e 5, docs/CONCEITOS_OBSERVABILIDADE.md, gitops/SECRETS-CONTRATO.md) | Adaptar a estrutura (diagrama dos três sinais, tabela de charts, runbook, evidências datadas e contrato de Secrets) aos novos nomes e acrescentar as seções SRE/ITSM exigidas na Fase 5. |

### Riscos e pegadinhas

- Annotations de regra e templates não interpolam variáveis de ambiente. O $$values usado no ensaio de 2026-11-09 chegou literal ao texto da annotation; foi corrigido para $values em 2026-11-10, e o check-grafana.py passou a reprovar esse padrão. Os prints do ensaio guardam o defeito.
- O Grafana 13.3.0 converte em número um segredo que pareça número, e o provisionamento falha. Por isso o Terraform recusa Integration Key do PagerDuty nesse formato; a saída é recriar a integração.
- Quando o datasource falha, o Grafana cria um alerta DatasourceError com os mesmos labels da regra, inclusive selfheal=true. Por isso a rota de self-healing também exige alertname; sem esse filtro, uma queda do Prometheus reiniciaria o serviço sem motivo.
- O webhook do Grafana não aceita header Authorization (usar authorization_scheme/authorization_credentials), e o corpo padrão não tem o event_type exigido pela API repository_dispatch (é preciso o payload template). O header X-GitHub-Api-Version está fixado em 2026-03-10.
- repository_dispatch só dispara workflows que estão na branch padrão: self-healing.yml precisa estar na main antes do ensaio. A trust OIDC da role usa o subject da main.
- O kubectl do runner ubuntu-latest era novo demais para o EKS 1.34 (a política aceita só 1 minor de diferença); a Fase 4 fixou v1.34.13. Reajustar à versão do novo cluster.
- Cooldown de 600 s: um disparo a menos de 10 min do último restart termina em 'cooldown' sem reiniciar. É preciso esperar pelo menos 10 min entre o ensaio e a gravação e confirmar alerta Normal e incidente resolvido.
- O rollout restart só resolve falha transitória em memória (flag-service com 1 réplica e 1 worker). Não recupera banco indisponível, e o /health continua 200, então a liveness probe não age; a documentação proíbe anunciar autorreparo de qualquer incidente.
- Com noDataState OK e metrics_expiration de 5m, a regra fica OK quando não há tráfego. Pela configuração (inferência, não testado), um serviço totalmente fora do ar que não gere spans também não dispara a regra de proporção 5xx. Na Fase 5, um SLO de disponibilidade pode precisar de um alerta complementar.
- Retenção do Prometheus de 2d/4GiB em PVC de 5Gi: insuficiente para janelas longas de SLO/error budget, sem recording rules (nenhuma regra própria encontrada na Fase 4).
- includeCollectorLogs começou false e foi ligado em 2026-11-10 para cumprir 'todos os logs dos contêineres'. Isso exige debug: null no agente e no gateway, para não criar ciclo de logs, e o agente roda como root por causa do storeCheckpoints.
- A pipeline de logs do gateway não sanitiza nada: a privacidade depende dos logs JSON com campos controlados nas aplicações. O código recebido na Fase 5 loga exceções cruas (f-string e %v) e lida com e-mail de ONG/voluntário e nome do doador.
- psycopg2: cursor_factory=RealDictCursor passado em cada conn.cursor() impede o instrumentador de envolver o cursor. A primeira prova saiu com 17 spans, sem os SELECT; a correção foi definir a factory no pool. O ngo-service da Fase 5 usa exatamente o padrão problemático.
- O SDK Python precisa inicializar depois do fork do Gunicorn (sem --preload), senão pools, threads e exporter nascem no processo errado.
- Nomes da Fase 4 estão fixados em muitos lugares: namespace togglemaster, service.namespace no código, uid/título do dashboard, regra, pasta, grupo, contact points, templates, ConfigMaps, grupo Kubernetes e allowlist (repetida em restart.sh, workflow, RBAC e testes), além de URLs do repositório no dispatch, no runbook_url e no $values das Applications. Esquecer um deles quebra a cadeia em silêncio.
- Sem Ingress, o acesso é por port-forward e o root_url é http://localhost:3000: os links das notificações (regra, painel, silenciar) só funcionam na máquina do apresentador.
- Os CRDs do Prometheus Operator exigem ServerSideApply. Na primeira instalação da camada terraform/k8s, o ArgoCD e seus CRDs precisam vir antes (apply com -target=helm_release.argocd) do kubernetes_manifest da Application.
- O gateway tem 1 réplica, sem alta disponibilidade. Não foram encontrados nos values scrape das métricas internas do Collector nem alerta para falha de exportação.
- PagerDuty: o trial dura 14 dias (conta da Fase 4 criada em 2026-10-28). No plano Free, o efeito sobre a Events API e as ações do Slack ficou marcado como INCERTO.
- New Relic: conta e endpoint da região US (EU exigiria outro endpoint). O enquadramento como conta education não foi comprovado (REQ-OBR-12/Q-04 da Fase 4). O Service Map global apareceu só no vídeo; o relatório usou o mapa de entidades de um trace.
- A evidência da Fase 4 dependeu de kubectl manual: psql de schema, Secret da chave com rollout restart, pod 'trafego' via kubectl run e falha via kubectl exec. Isso conflita com o REQ-OBR-02 da Fase 5 (zero deploy manual via kubectl).
- O ambiente da Fase 4 foi encerrado em 2026-11-12 (camadas e bucket de estado removidos), e os estados não devem ser reutilizados. O guia interno estimava US$ 0,41/h com o ambiente ligado, mas os documentos públicos dizem não haver estimativa de custo vigente.
- Na Fase 5, o código recebido não tem consumidor da fila SQS nem chamadas HTTP entre os três serviços: o trace multi-serviço e o par produtor/consumidor que provaram o tracing na Fase 4 não se reproduzem sem mudança de código.
- O donation-service da Fase 5 declara go 1.21, usa QueryRow/Query sem contexto, dispara 'go a.sendNotificationEvent(d)' sem contexto e não trata SIGTERM. Sem refatorar, os spans de banco e SQS não ficariam ligados ao trace da requisição.

### Dependências externas

- Conta New Relic (região US, endpoint otlp.nr-data.net) com chave do tipo Ingest - License de 40 caracteres, informada por TF_VAR_new_relic_license_key e entregue ao gateway pelo Secret newrelic-license (chave NEW_RELIC_LICENSE_KEY)
- Conta PagerDuty com serviço próprio (na Fase 4, 'ToggleMaster Fase 4'), integração Events API V2, escalation policy, regras de notificação e app móvel; a Integration Key (32 alfanuméricos que não pareça número) vai por TF_VAR_pagerduty_integration_key para o Secret grafana-notificacoes
- Workspace Slack com canal de incidentes (na Fase 4, #incidentes-tech-challenge) e app com Incoming Webhook (a URL é o próprio segredo), por TF_VAR_slack_webhook_url; e app do PagerDuty no Slack autorizado por OAuth e conectado ao canal (/pd link, /pd connect, preset All Updates)
- Fine-grained PAT do GitHub restrito ao repositório, com permissão Contents: Read and write (exigida pela API repository_dispatch), por TF_VAR_github_dispatch_token para a variável GITHUB_DISPATCH_TOKEN do Grafana
- GitHub repository Variables (não são segredos): AWS_REGION, AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME para o self-healing, além de AWS_ROLE_ARN e ECR_REGISTRY do CI
- AWS: provedor OIDC do GitHub e role de self-healing (eks:DescribeCluster), EKS com authentication_mode API_AND_CONFIG_MAP e access entry, StorageClass gp3 (EBS CSI) para os PVCs de Prometheus e Loki
- Repositórios Helm públicos prometheus-community, grafana e open-telemetry; imagens otel/opentelemetry-collector-contrib 0.163.2, grafana 13.3.0-distroless e loki 3.6.11
- Senha de admin do Grafana gerada pelo Terraform (random_password) no Secret grafana-admin; senha inicial do ArgoCD lida do Secret para login
- Arquivo .env local ignorado pelo Git como origem dos TF_VAR_* e da chave New Relic do ensaio local; nunca versionado nem exibido em vídeo
- Repositório público lido pelo ArgoCD sem token; se for privado, token de leitura (Contents: Read-only) separado do token de dispatch
- Docker com engine Linux, Bash/Git Bash e Python 3 para os ensaios locais; kustomize 5.4.3 e PyYAML 6.0.3 no CI

### Passos que ficaram manuais na Fase 4 (a eliminar na Fase 5)

- Criar e configurar as contas SaaS pelo console: chave Ingest - License no New Relic; serviço, integração Events API V2, escalation policy, regras de notificação e app móvel no PagerDuty; canal, app e Incoming Webhook no Slack; integração PagerDuty↔Slack com /pd link, /pd connect e troca do preset para All Updates
- Criar o fine-grained PAT de dispatch no GitHub, preencher o .env local e exportar à mão os TF_VAR_* na janela do shell antes de cada plan/apply da camada k8s
- Cadastrar com gh variable set as Variables AWS_SELF_HEALING_ROLE_ARN (output da base) e EKS_CLUSTER_NAME
- Aplicar a camada terraform/k8s em dois tempos a partir do laptop: plan/apply com -target=helm_release.argocd, esperar o CRD e depois plan/apply completo
- Preencher o overlay com endpoints e roles IRSA via sed, fazer commit/push e abrir/mergear o PR para a main (o self-healing só responde a repository_dispatch na branch padrão)
- Inicializar os schemas com kubectl run psql < init.sql, gerar a chave de serviço pela API via port-forward, criar o Secret com kubectl create ... | kubectl apply e fazer rollout restart manual do evaluation-service
- Criar o pod gerador de tráfego 'trafego' com kubectl run (chave em variável de ambiente) e as flags de demonstração com curl
- Abrir port-forwards para Grafana (3000), ArgoCD (8080) e evaluation (8004) e ler as senhas de admin dos Secrets
- Disparar a falha controlada com kubectl exec ... curl POST /admin/fault e, como contingência declarada, desligá-la à mão
- Esperar pelo menos 10 min de cooldown entre o ensaio e a gravação e conferir a regra Normal e o incidente resolvido
- Capturar os prints e montar a linha do tempo consultando Loki, gh run view e Slack, cobrindo chaves e e-mails antes de versionar
- Rodar à mão os ensaios locais (bash scripts/test-observability.sh e scripts/test-observability-newrelic.sh) e limpar o laboratório com docker compose down -v
- Destruir por plano salvo, camada por camada, e conferir/remover à mão volumes EBS órfãos (aws ec2 describe-volumes / delete-volume)

### Dúvidas levantadas pela leitura (histórico)

- Como provocar a falha controlada no donation-service na demonstração? A Fase 4 usou um endpoint /admin/fault autenticado no flag-service, mas os três serviços da Fase 5 não têm autenticação. Podemos criar um endpoint de falha (e como protegê-lo) ou preferem outro mecanismo?
- O código recebido não tem chamadas HTTP entre os serviços nem consumidor da fila SQS. Para o tracing distribuído, podemos acrescentar alguma interação (ex.: donation-service validar o ngo_id no ngo-service, ou um consumidor da fila), ou aceitamos três serviços independentes com PostgreSQL/SQS/DynamoDB no Service Map?
- Quais metas e qual janela dos SLOs do donation-service (ex.: percentual de sucesso, limiar de latência em ms, janela de 7, 28 ou 30 dias)? Isso define a retenção e o disco do Prometheus e os buckets do histograma.
- O self-healing deve cobrir só o donation-service ou os três serviços? A ação automática continua sendo apenas o rollout restart?
- Vamos reutilizar as contas SaaS da Fase 4 (New Relic US, PagerDuty, workspace/canal do Slack) ou criar novas? O trial de 14 dias do PagerDuty da Fase 4 provavelmente expirou: plano Free ou novo trial?
- Qual nome substitui 'togglemaster' (namespace, service.namespace, prefixos de recursos) e qual é o repositório/organização definitivo da Fase 5, usado na URL do repository_dispatch e no $values do ArgoCD?
- Mantemos o New Relic como APM (o README da Fase 5 sugere Datadog ou New Relic)? A conta tem o recurso de IA (Applied Intelligence) exigido no REQ-OBR-23? Não há nada disso na Fase 4.

<a id="4-svc"></a>
## 4. Serviços, contêineres e colaboração

Na Fase 4 os cinco serviços (auth e evaluation em Go 1.25; flag, targeting e analytics em Python 3.12/Flask) usam o mesmo padrão de Dockerfile multi-stage, com usuário não root, e nenhum HEALTHCHECK no Dockerfile. A saúde é verificada pelo healthcheck do Compose e por readiness/liveness em /health no Kubernetes. A instrumentação é só de traces, com o SDK OpenTelemetry exportando por OTLP/HTTP. Ela é opt-in: só liga quando existe endpoint OTEL_* e OTEL_SDK_DISABLED=true prevalece. A propagação é W3C sem baggage, e os logs saem em JSON no stdout com trace_id/span_id, sem SQL, chaves ou mensagens de erro. As métricas de aplicação vêm do spanmetrics no gateway do Collector, e os logs são lidos pelo agent. Em Go, o otelhttp cobre o handler e o transport, e há spans manuais de PostgreSQL, Redis e SQS, com traceparent em MessageAttributes. O graceful shutdown em Go drena primeiro as requisições, depois os produtores SQS, e só então faz o flush do SDK. Em Python, os instrumentadores Flask/requests/psycopg2 são inicializados no worker do Gunicorn (sem --preload), e há spans manuais para o consumidor SQS e para o DynamoDB. Os arquivos telemetry.go e telemetry.py são cópias idênticas em cada serviço. Cada serviço tem testes unitários sem rede, e o flag-service tem uma falha proposital em memória (/admin/fault) para a demonstração de self-healing. No CI, cinco workflows finos chamam _ci-go.yml/_ci-python.yml, que rodam em paralelo build+testes (go test -count=1; pytest se houver tests/), lint, SAST e SCA (Trivy CRITICAL). O PR também constrói e escaneia a imagem sem publicar. Só o push na main publica no ECR via OIDC e grava a tag no GitOps, e um workflow à parte roda o ensaio Compose dos cinco serviços com Moto. A colaboração fica em 00_COLAB_IA, e .claude/CLAUDE.md é um ponteiro para essa pasta. Os seis arquivos são: LEIA-PRIMEIRO (protocolo e regras), PENDENCIAS (checklist vigente no topo), LOG (entradas datadas, mais recente no topo, cada uma terminando em 'Estado p/ próximo agente'), DECISOES (ADRs D-0NN), DOSSIE (contexto compactado) e ORGANIZACAO (pastas e nomes). Todo documento tem TL;DR e 'Última atualização: data, agente'. Antes de editar, a versão anterior é copiada para _ARQUIVO_MORTO/<data>_<motivo>_vNN com DE-PARA, e correções viram retificações datadas, sem reescrever o histórico. O trabalho intermediário fica em 02_TRABALHO, e as evidências brutas ficam em subpastas qa-*/validacao-local-*, ignoradas pelo Git. Os entregáveis ficaram em docs/: gravacao (roteiro gerado de um JSON), relatorio (PDF gerado de dados-entrega.json) e evidencias (pasta datada, índice e entrada-local ignorada).

### Arquivos-chave

| Caminho | Papel |
|---|---|
| `.claude/CLAUDE.md` | Ponteiro interno para assistentes: TL;DR do estado, ordem de leitura (LEIA-PRIMEIRO → PENDENCIAS → topo do LOG → DOSSIE/DECISOES), regras de idioma, de evidência e de segredos, e fechamento com teste de handoff. Foi movido da raiz em 2026-11-09 (D-023). |
| `00_COLAB_IA/LEIA-PRIMEIRO.md` | Protocolo de colaboração: ritual de retomada em 5 passos, IDs D-/P-/F-, limites e conflitos (⚠️ CONFLITO, [INCERTO]), regras herdadas da Fase 3 (prefixo F3-, cinco estados de evidência, segredos, Git, shell no Windows) e retificações vigentes datadas no topo. |
| `00_COLAB_IA/PENDENCIAS_E_PROXIMOS_PASSOS.md` | Checklist vigente: bloco 'Pedido vigente — data, agente' no topo com [x]/[ ], pedidos anteriores mantidos como histórico, autorizações do usuário (D1–D5), calendário e triagem das pendências herdadas (F3-P-*). |
| `00_COLAB_IA/LOG_DE_TRABALHO.md` | Diário append-only, mais recente no topo. Cabeçalho '## AAAA-MM-DD HH:MM (America/Sao_Paulo, UTC-03:00) — Agente (modelo) — Título' e campos Pedido/Feito/Plano/Decisões/Arquivos/Verificação/Não provado/Estado p/ próximo agente. |
| `00_COLAB_IA/DECISOES.md` | ADRs D-001..D-026 (Contexto/Decisão/Alternativas/Status, com palavras literais do usuário e limites de autorização), mais 59 decisões herdadas da Fase 3 (F3-D-001..024 e F3-SN-01..35) com status vigente/revisar/superada/histórica. |
| `00_COLAB_IA/DOSSIE_CONTEXTO.md` | Contexto compactado: revalidações e retificações vigentes no topo, seções numeradas (objetivo, regras, caminhos, ferramentas, glossário, instruções ao próximo assistente) e snapshots datados por marco (§13–§31). Inclui a herança da Fase 3 (§20: números medidos, boas práticas, armadilhas, lições de vídeo e relatório). |
| `00_COLAB_IA/ORGANIZACAO_DE_PASTAS.md` | Destino de cada artefato e convenções de nome (descrição + data ISO + _vNN; documentos públicos em MAIUSCULAS_COM_UNDERSCORE.md; evidência datada). Define o que nunca se versiona e as regras do arquivo morto (mover em commit próprio, histórico não se reescreve). |
| `00_COLAB_IA/02_TRABALHO/HANDOFF_GRAVACAO_2026-11-09_v01.md` | Modelo de documento de handoff: autorizações e estado, linha do tempo comprovada (UTC e local), capturas existentes, artefatos em revisão, próximas ações em ordem, geradores e runtime. |
| `00_COLAB_IA/_ARQUIVO_MORTO/2026-11-09_02_TRABALHO-historico/DE-PARA.md` | Exemplo do de-para obrigatório ao mover auxiliares: tabela com o caminho antigo e o novo. |
| `00_COLAB_IA/02_TRABALHO/limpeza-2026-11-09_v01/manifesto-exclusoes.json` | Manifesto de exclusões (caminho, SHA-256, blob e git show) para recuperar os 121 arquivos removidos na limpeza D-022. |
| `services/auth-service/Dockerfile` | Padrão Go: golang:1.25-alpine → alpine:3.24, binário estático com -trimpath e -ldflags '-s -w', usuário app não root, ENTRYPOINT. O do evaluation-service é idêntico, exceto pela porta. |
| `services/flag-service/Dockerfile` | Padrão Python: builder python:3.12-slim gera wheels, runtime slim com libpq5/ca-certificates, usuário app, CMD 'exec gunicorn --bind 0.0.0.0:${PORT}'. Targeting e analytics são idênticos, exceto pela porta. |
| `services/auth-service/telemetry.go` | Bootstrap OTel Go opt-in, logger slog JSON correlacionado, instrumentHandler (otelhttp, sem /health), serveHTTP com graceful shutdown, dependencySpan e shutdownTelemetry. É cópia idêntica do arquivo do evaluation-service. |
| `services/auth-service/telemetry_test.go` | Testes Go genéricos: receptor OTLP HTTP em memória, contexto pai, logs sem dados privados, opt-in/desligado e drenagem no SIGTERM. |
| `services/evaluation-service/sqs.go` | Span PRODUCER 'sqs publish' com traceparent/tracestate em MessageAttributes, corpo de negócio intacto, context.WithoutCancel + timeout de 5 s e WaitGroup de produtores. |
| `services/flag-service/telemetry.py` | Bootstrap OTel Python (configure_telemetry com flags postgres/requests_client, JsonFormatter, instrument_flask sem /health, record_error, traced_operation). É cópia idêntica nos três serviços Python. |
| `services/flag-service/app.py` | Pool psycopg2 com cursor_factory=RealDictCursor no connect (preserva os spans SQL) e falha proposital em memória (/admin/fault autenticado; /health segue 200). |
| `services/analytics-service/app.py` | Consumidor SQS: span CONSUMER com contexto extraído dos MessageAttributes, spans CLIENT dynamodb.PutItem e sqs.DeleteMessage, ack só depois de persistir. |
| `services/flag-service/tests/test_telemetry.py` | Testes unittest (rodados com pytest no CI): contexto HTTP, exclusão do /health, erro sem mensagem, opt-in, propagação W3C via requests e span SQL com privacidade. |
| `services/flag-service/tests/test_fault.py` | Sete testes da falha proposital: 5xx nas rotas de flags, /health saudável, processo novo nasce limpo, autenticação e validação do corpo. |
| `.github/workflows/_ci-go.yml` | Reutilizável Go: build e go test, golangci-lint v2.13.2, gosec v2.29.0, Trivy fs, image-scan no PR, image (needs dos 4 jobs, OIDC, ECR) e gitops (kustomize edit, laço de 5 tentativas). |
| `.github/workflows/_ci-python.yml` | Reutilizável Python: compileall + pytest se houver tests/, flake8 (erros) + pylint com requirements instalados, bandit -ll, Trivy fs/imagem; publicação idêntica à de Go. |
| `.github/workflows/flag-service.yml` | Chamador fino por serviço: gatilhos push/PR em main e dev com filtro de caminho, workflow_dispatch, teto de permissões e concurrency por serviço e ref. |
| `.github/workflows/compose-integration.yml` | Ensaio ponta a ponta dos cinco serviços em Compose com Moto (scripts/test-compose.sh), com paths-ignore de documentação, logs em caso de falha e down -v sempre. |
| `docker-compose.yaml` | Healthchecks: pg_isready, redis-cli ping, wget para as imagens Alpine e python urllib para as imagens slim (interval 10 s, retries 5, start_period 15 s). |
| `gitops/base/kustomization.yaml` | configMapGenerator otel-config (endpoint do gateway, http/protobuf, parentbased_always_on) aplicado aos cinco Deployments. |
| `gitops/base/flag-service/deployment.yaml` | Padrão de Deployment: resources requests/limits e readiness/liveness httpGet /health. Não há securityContext nem preStop. |
| `.pylintrc` | Corte fail-under 7.0, max-line-length 120 e regras de estilo desligadas, cada uma com justificativa. |
| `.trivyignore` | Exceções nominais e datadas (3 CVEs do perl-base em python:3.12-slim), com revisão marcada para 2026-10-15 e já vencida. |
| `.gitignore` | Bloqueia tfstate/tfvars/tfplan/.env/chaves/kubeconfig/vídeos e ignora 02_TRABALHO/qa-* e validacao-local-* ('ignorado não é descartável') e docs/evidencias/entrada-local/*. |
| `docs/gravacao/README.md` | Roteiro de 10 cenas cronometradas (21 min + 4 de margem, limite de 25), cada uma com Tela, ações, fala, Confira e Fonte (página do enunciado), mais checklists antes do REC e antes de entregar. |
| `docs/gravacao/roteiro-conteudo.json` | Fonte única das cenas (n, time, title, tool, actions, speech, proof, source, command), consumida pelos geradores de PPTX/PDF. |
| `docs/gravacao/PASSO_A_PASSO_POR_CENA.md` | Mesa de gravação (terminais A–D, túneis em laço, abas) e cada frase do roteiro ligada a tela, clique, resultado esperado e comando. |
| `docs/relatorio/README.md` | Mapa 'exigência do enunciado (p. 6) → página do PDF', origem dos dados e procedimento para incluir o link do vídeo e gerar o PDF de novo. |
| `docs/relatorio/dados-entrega.json` | Fonte de dados do relatório: participantes, repositório, video_url, execuções e linha do tempo da gravação. |
| `00_COLAB_IA/02_TRABALHO/entrega-relatorio-2026-11-11_v03/build_relatorio.py` | Gerador do relatório: JSON + prints → HTML → PDF pelo Edge headless; os prints só são recortados (Pillow), nunca editados. |
| `docs/evidencias/README.md` | Índice dos prints (arquivo, o que mostra, página do relatório, ★ nos 4 obrigatórios) e tabela de registros da gravação (horário, evento, fonte). |
| `docs/evidencias/entrada-local/LEIA-ME.md` | Pasta local ignorada para prints ainda sem revisão, com nomes 01-grafana.png..04-self-healing.png e regra de cobrir segredos antes de publicar. |
| `docs/CI-CD.md` | Guia público de leitura dos workflows: o que cada um verifica, quando roda, como ler o grafo e o que demonstra o self-healing. |

### Decisões técnicas da Fase 4

- Dockerfile Go multi-stage: builder golang:1.25-alpine com cache de go mod download e build CGO_ENABLED=0 GOOS=linux -trimpath -ldflags='-s -w'; runtime alpine:3.24 (subiu de 3.20 por fim de suporte, D-021) com ca-certificates, usuário app não root e ENTRYPOINT ['/app/service'] (services/auth-service/Dockerfile; 00_COLAB_IA/DECISOES.md D-021)
- Dockerfile Python multi-stage: builder python:3.12-slim com build-essential/gcc/libpq-dev gerando wheels; runtime python:3.12-slim só com libpq5/ca-certificates, usuário app, chown e CMD ['sh','-c','exec gunicorn --bind 0.0.0.0:${PORT:-800x} app:app'], com exec para repassar sinais (services/flag-service/Dockerfile)
- Sem instrução HEALTHCHECK nos Dockerfiles: a saúde fica no Compose (wget nas imagens Alpine, python urllib nas slim; interval 10 s, timeout 5 s, retries 5, start_period 15 s) e no Kubernetes (readiness e liveness httpGet /health). O /health devolve {"status":"ok"} e não consulta dependências (docker-compose.yaml; gitops/base/*/deployment.yaml; 00_COLAB_IA/DOSSIE_CONTEXTO.md §20.1)
- Imagens base dos serviços fixadas por tag, não por digest; só o Collector e o Moto do Compose são pinados por digest (services/*/Dockerfile; docker-compose.otel.yaml; docker-compose.integration.yaml)
- OTel opt-in: sem OTEL_EXPORTER_OTLP_ENDPOINT/OTEL_EXPORTER_OTLP_TRACES_ENDPOINT não se cria exporter (Go usa noop provider); OTEL_SDK_DISABLED=true prevalece (services/auth-service/telemetry.go; services/flag-service/telemetry.py; D-016)
- Somente traces pelo SDK, exportados por OTLP/HTTP protobuf com BatchSpanProcessor/WithBatcher; sem SDK de métricas ou de logs nas apps. Métricas vêm do spanmetrics no gateway, e os logs JSON do stdout são coletados pelo agent DaemonSet (README.md; services/*/README.md)
- Propagação somente W3C TraceContext, sem baggage; resource com service.name e service.namespace=togglemaster fixo no código (telemetry.go/telemetry.py)
- Go: OTel 1.46.0 + otelhttp 0.71.0 (handler com filtro de /health, transport no http.Client para propagar contexto). Spans CLIENT manuais para PostgreSQL e Redis só com db.system.name/db.operation.name (sem SQL, chave ou valor). A SQS usa aws-sdk-go v1 com propagação manual em MessageAttributes (services/auth-service/go.mod; services/evaluation-service/evaluator.go e sqs.go)
- Python: SDK 1.45.1 + instrumentações 0.66b1 (flask, requests, psycopg2 com capture_parameters=False e enable_commenter=False), configuradas por código no import do app, dentro do worker do Gunicorn, sem --preload e sem opentelemetry-instrument, para evitar spans duplicados (services/flag-service/telemetry.py e requirements.txt)
- RealDictCursor definido no SimpleConnectionPool/connect, e não em conn.cursor(), para não descartar a factory instrumentada; o gate de integração exige spans PostgreSQL nos três serviços que usam o banco (services/flag-service/app.py; D-016)
- Analytics: span CONSUMER 'sqs.process' com contexto extraído dos MessageAttributes, spans CLIENT dynamodb.PutItem e sqs.DeleteMessage e ack só após persistir; sem auto-instrumentação botocore, para não capturar payload nem duplicar spans (services/analytics-service/app.py)
- Logs JSON com campos controlados (time, level, service.name, message/event, rota, status) mais trace_id/span_id; erros registram só error.type, sem mensagem nem stacktrace (telemetry.go; telemetry.py)
- Graceful shutdown em Go: signal.NotifyContext(SIGINT, SIGTERM) → server.Shutdown com timeout de 10 s → espera das requisições ativas → espera dos produtores SQS (afterRequests) → flush do SDK com contexto novo de 5 s; ReadHeaderTimeout de 5 s (services/auth-service/telemetry.go; services/evaluation-service/main.go)
- Telemetria duplicada de propósito em cada contexto Docker: telemetry.go é idêntico nos dois serviços Go e telemetry.py nos três Python (cabeçalhos dos arquivos)
- OTEL_* comuns via configMapGenerator otel-config (endpoint http://otel-gateway.observability.svc.cluster.local:4318, http/protobuf, parentbased_always_on); o sufixo de hash reinicia os pods quando o valor muda; OTEL_SERVICE_NAME fica no ConfigMap de cada serviço (gitops/base/kustomization.yaml; gitops/base/flag-service/configmap.yaml)
- CI: 5 chamadores finos + 2 workflows reutilizáveis por linguagem (input service). build/lint/sast/sca rodam em paralelo; image-scan sem push no PR e no dispatch; image com needs [build, lint, sast, sca] só em push na main, OIDC e ECR, tag v1.0.0-<sha7> + latest; gitops com kustomize 5.4.3 edit set image, commit [skip ci] e laço de 5 tentativas fetch/reset/edit/push (.github/workflows/_ci-go.yml; _ci-python.yml)
- Testes no CI: Go com go build -v ./... e go test -count=1 -v ./...; Python com compileall e pytest -v se existir tests/ (testes escritos em unittest). pylint roda com requirements instalados e fail-under 7.0 via .pylintrc; flake8 falha só em E9/F63/F7/F82; gosec com -severity high -confidence medium; bandit -ll; Trivy pinado por SHA, CRITICAL, exit-code 1, ignore-unfixed false e .trivyignore nominal (.github/workflows/_ci-*.yml; .pylintrc; .trivyignore)
- Ensaio de integração no CI: docker compose com .env.example fictício + Moto (SQS/DynamoDB), up --build --wait e test-flow.py, projeto tc04-integration, timeout de 20 min e paths-ignore de 00_COLAB_IA/**, docs/** e **.md. O ensaio de traces (test-observability.sh, gate de 19 spans) é só local (.github/workflows/compose-integration.yml; scripts/test-compose.sh; scripts/test-observability.sh)
- Falha proposital só em memória: POST /admin/fault autenticado faz /flags responder 503 com JSON; /health continua 200 para que a liveness não reinicie o pod e quem cure seja a cadeia alerta → self-healing (services/flag-service/app.py; D-019)
- Diário de colaboração em 00_COLAB_IA com seis arquivos. IDs D-### (decisões), P-### (pendências) e F-### (achados); prefixo F3- para a herança da Fase 3; Q-NN para dúvidas ao tutor; REQ-OBR-NN para requisitos; B0–B6 e E0–E7 para blocos e etapas; D1–D5 para autorizações pontuais do usuário (00_COLAB_IA/LEIA-PRIMEIRO.md; PENDENCIAS_E_PROXIMOS_PASSOS.md)
- Todo documento começa com TL;DR e 'Última atualização: AAAA-MM-DD, agente'. Retificações entram como seções datadas no topo ('Retificação vigente — data'), sem apagar o texto antigo (00_COLAB_IA/*.md)
- Nomes: descrição + data ISO + _vNN (ex.: PREPARACAO_B3_2026-11-05_v02.md); nunca 'copia' ou 'final'; documentos públicos em docs/ com MAIUSCULAS_COM_UNDERSCORE.md; snapshots em _ARQUIVO_MORTO/AAAA-MM-DD_<motivo>[_vNN] espelhando os caminhos relativos, com DE-PARA.md (00_COLAB_IA/ORGANIZACAO_DE_PASTAS.md)
- D-018: documentos públicos sem citar assistentes nem IDs internos (que ficam só no diário); os commits da Fase 4 foram feitos sem trailer Co-Authored-By de assistente (00_COLAB_IA/DECISOES.md D-018; LOG 2026-11-03 11:31; git log)
- Git: trabalho na dev, PR para a main com merge --merge, nunca --delete-branch; o robô comita tags direto na main e a dev é sincronizada depois; git add arquivo por arquivo (nunca '.' ou -A) e varredura do diff antes de cada commit (00_COLAB_IA/LEIA-PRIMEIRO.md; docs/CI-CD.md)
- Relatório: PDF A4 paisagem gerado a partir de docs/relatorio/dados-entrega.json → HTML → Edge headless, com prints recortados e nunca editados; versões v01/v02 mantidas como histórico na mesma pasta (D-025; 00_COLAB_IA/02_TRABALHO/entrega-relatorio-2026-11-11_v03/build_relatorio.py)
- Roteiro orientado a dados: roteiro-conteudo.json alimenta o README, o PPTX e o PDF v03 (19 slides, fala nas notas do apresentador); o gerador confere as falas com o JSON e os comandos com o passo a passo (docs/gravacao/; 00_COLAB_IA/02_TRABALHO/entrega-gravacao-2026-11-11_v03/build_guia_unico.py)

### O que reaproveitar na Fase 5

| Item | Como reaproveitar |
|---|---|
| Dockerfile Go multi-stage (services/auth-service/Dockerfile) e .dockerignore Go | Usar como base do donation-service: ajustar a porta do EXPOSE, a versão do builder conforme o go.mod do serviço e o nome do binário; manter usuário não root e build estático. |
| Dockerfile Python multi-stage (services/flag-service/Dockerfile) e .dockerignore Python | Base do ngo-service (com libpq) e do volunteer-service (sem Postgres, pode dispensar libpq-dev/libpq5); manter wheels no builder, usuário app e 'exec gunicorn' sem --preload. |
| services/auth-service/telemetry.go (bootstrap OTel, slog JSON correlacionado, instrumentHandler, serveHTTP com graceful shutdown, dependencySpan) | Copiar para o donation-service trocando service.namespace 'togglemaster' e o nome padrão; usar dependencySpan nas queries PostgreSQL e o afterRequests para drenar os produtores SQS. |
| services/auth-service/telemetry_test.go | Copiar para o donation-service: os testes são genéricos (receptor OTLP em memória, opt-in/desligado, graceful shutdown); só ajustar nomes. |
| Padrão de produtor SQS com contexto W3C em MessageAttributes (services/evaluation-service/sqs.go) | Aplicar ao evento de doação: span PRODUCER, traceparent/tracestate em MessageAttributes, corpo de negócio intacto, context.WithoutCancel + timeout e WaitGroup drenado no shutdown; adequar ao SDK AWS que o donation-service já usa. |
| Spans manuais de PostgreSQL em Go e teste com go-sqlmock (services/auth-service/handlers.go e handlers_test.go) | Replicar no donation-service: span CLIENT por operação, sem SQL nem parâmetros nos atributos, e teste de privacidade dos logs e de cancelamento. |
| services/flag-service/telemetry.py | Copiar idêntico para o ngo-service (postgres=True) e o volunteer-service (sem postgres); trocar service.namespace. |
| Pool psycopg2 com cursor_factory=RealDictCursor no connect (services/flag-service/app.py) | Seguir no ngo-service para não perder os spans SQL; incluir o teste equivalente do PostgresTracingTests. |
| Spans manuais DynamoDB/SQS com traced_operation (services/analytics-service/app.py) | Aplicar no volunteer-service (DynamoDB) sem auto-instrumentação botocore; registrar só error.type. |
| Testes Python de telemetria (services/*/tests/test_telemetry.py) | Adaptar para ngo e volunteer: contexto HTTP, exclusão do /health, opt-in, propagação W3C e privacidade; manter o sys.path para rodar com pytest a partir da pasta do serviço. |
| Workflows reutilizáveis .github/workflows/_ci-go.yml e _ci-python.yml + chamadores finos (flag-service.yml) | Copiar os reutilizáveis e criar 3 chamadores (ngo, donation, volunteer) com filtros de caminho; revisar variáveis ECR/OIDC, versões fixadas e o comentário obsoleto de 'sem testes'. |
| Ensaio de integração em Compose (compose-integration.yml, scripts/test-compose.sh, docker-compose.integration.yaml com Moto, scripts/integration/test-flow.py) | Manter a estrutura (projeto isolado, .env.example fictício, up --wait, logs em caso de falha, down -v); reescrever o fluxo de negócio do test-flow para ONGs, doações e voluntários. |
| Health checks: endpoint /health, healthcheck do Compose e readiness/liveness com resources (docker-compose.yaml; gitops/base/*/deployment.yaml) | Repetir o padrão nos 3 serviços (wget para Alpine, python urllib para slim) com probes httpGet /health e requests/limits. |
| configMapGenerator otel-config e OTEL_SERVICE_NAME por ConfigMap (gitops/base/kustomization.yaml) | Reaproveitar trocando o endpoint do gateway e os nomes dos serviços. |
| .pylintrc, .trivyignore e .gitignore | Copiar .pylintrc; recomeçar o .trivyignore vazio e só incluir exceção nominal e datada após medir as imagens reais; adaptar caminhos do .gitignore (02_TRABALHO/qa-*, validacao-local-*, entrada-local). |
| Falha proposital em memória (/admin/fault autenticado, /health 200) + tests/test_fault.py | Usar só se o mapa de requisitos da Fase 5 exigir demonstrar incidente ou self-healing; replicar no serviço escolhido. |
| Estrutura de colaboração 00_COLAB_IA (LEIA-PRIMEIRO, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO + 02_TRABALHO + _ARQUIVO_MORTO) e .claude/CLAUDE.md como ponteiro | Recriar enxuta para a Fase 5 com o mesmo protocolo (ritual de retomada, IDs, TL;DR + Última atualização, LOG com 'Estado p/ próximo agente', snapshots com DE-PARA, teste de handoff), sem copiar o conteúdo histórico da Fase 4. |
| Formatos de registro (cabeçalho do LOG, ADR D-0NN com Contexto/Decisão/Alternativas/Status, checklist 'Pedido vigente' em PENDENCIAS, documento de handoff) | Copiar os modelos de formato para os novos arquivos da Fase 5. |
| docs/gravacao (roteiro-conteudo.json → README/PPTX/PDF, PASSO_A_PASSO_POR_CENA.md, COMANDOS.md) | Manter a estrutura de cenas (tela, ações, fala, Confira, Fonte com página do enunciado) e reescrever o conteúdo para a SolidaryTech e para o limite de duração da Fase 5. |
| docs/relatorio (dados-entrega.json + build_relatorio.py, HTML → Edge headless → PDF; mapa exigência → página) | Reaproveitar o gerador trocando os dados, os prints e as seções conforme o que a Fase 5 pede no relatório. |
| docs/evidencias (pasta datada com NN-tema.png, README índice com ★ nos obrigatórios, entrada-local ignorada) | Copiar a estrutura e as regras (cobrir segredos antes de publicar; registros da gravação com horário e fonte). |
| docs/CI-CD.md e scripts/security-check.sh | Adaptar o guia dos workflows aos 3 serviços e os padrões de segredo da varredura. |

### Riscos e pegadinhas

- Limite de uso e créditos interrompeu várias rodadas de subagentes que liam muito antes de gravar, e o trabalho se perdeu (D-007). Regra adotada: gravar cada artefato assim que fica pronto e registrar no LOG o estado parcial antes de parar.
- pylint sem as dependências do serviço reprova (E0401 em todo import de terceiro; notas de 5,5–5,9 contra o corte de 7,0). A correção foi instalar o requirements antes do lint (_ci-python.yml; LOG 2026-11-01).
- Sobrescrever cursor_factory=RealDictCursor em conn.cursor() descarta a factory instrumentada e faz os spans SQL sumirem sem erro; um trace de 17 spans chegou a ser aceito antes de o gate exigir spans PostgreSQL (D-016).
- Gunicorn com --preload ou combinado com opentelemetry-instrument quebra ou duplica a instrumentação: o SDK precisa nascer no worker, depois do fork (services/*/README.md).
- Upgrade de segurança em cascata: golang.org/x/crypto v0.55.0 elevou o go.mod para 1.25 e obrigou a atualizar a imagem do builder, o gosec e o golangci-lint (DOSSIE §20.4). Depois, o Trivy apontou o Alpine 3.20 sem suporte, e foi preciso subir para 3.24 (D-021).
- Imagens base por tag e exceções do .trivyignore com data de revisão vencida (F-022); o Trivy local e o do CI já divergiram de versão. Reescanear as imagens reais antes de cada entrega.
- /health não consulta banco nem dependências, e readiness e liveness usam o mesmo endpoint: o pod pode estar 'saudável' com o serviço quebrado. Achados de aplicação não corrigidos: F-017 (falha do targeting vira resultado true) e F-018 (auth responde 401 para erro de banco).
- Manifestos Kubernetes sem securityContext, terminationGracePeriodSeconds ou preStop; o non-root vem só do USER do Dockerfile. A thread do worker SQS do analytics é daemon e não tem parada graciosa.
- Comentários desatualizados geram deriva de documentação: o _ci-python.yml diz que nenhum serviço Python tem testes; os deployments citam ESO; IDs internos da Fase 3 em comentários colidem com os da Fase 4 (LEIA-PRIMEIRO).
- Dependências Python antigas fixadas (Flask 2.2.2, requests 2.28.1, gunicorn 20.1.0) e o analytics com Flask, gunicorn e setuptools sem versão (F3-P-113); pytest no job build e bandit instalados sem versão.
- O cache do evaluation (por nome da flag, TTL de 30 s) esconde chamadas: foi preciso criar um pod gerador de tráfego e flags exclusivas para obter trace sem cache. Esse pod recebeu a chave por variável de ambiente, visível com kubectl describe.
- Windows: no Git Bash, 'python' pode cair no atalho da Microsoft Store; o PowerShell 5.1 não tem &&; foram necessários COMPOSE_PATH_SEPARATOR e MSYS_NO_PATHCONV; o Git Credential Manager travava o push (contornado com o helper do gh só no comando); comparações do LOG exigem normalizar CRLF/LF.
- Contêineres Docker locais nas portas 8001–8005 responderam no lugar dos túneis do cluster durante o ensaio de gravação (PASSO_A_PASSO_POR_CENA.md).
- O repositório ficou público em 2026-11-09: tudo o que for commitado é público. O histórico guarda nomes e RMs da Fase 3 e o ID da conta antiga, e o PDF com RMs foi publicado por decisão do usuário (D-023, D-025).
- O usuário colou segredos e uma senha no chat; os agentes não os usaram nem registraram, e foi recomendada a rotação (D-020). Regra: só conferir presença e formato, nunca o valor.
- Sem proteção de branch, um check vermelho não impede o merge; o robô comita direto na main, e a dev precisa ser sincronizada antes de novas edições.
- O teste integrado de traces (19 spans) e a exportação ao New Relic não rodam no CI (F-020); CI verde não prova cluster, sync do ArgoCD nem funcionamento na AWS (cinco estados de evidência).
- Registro não é prova: entradas de um agente precisam ser conferidas contra o código, o Git e os runs antes de serem tratadas como fato; houve correções de horário UTC/local e de nomes (ex.: nome do cluster) via novas entradas.

### Dependências externas

- Repository Variables do GitHub: AWS_REGION, ECR_REGISTRY, AWS_ROLE_ARN, AWS_SELF_HEALING_ROLE_ARN e EKS_CLUSTER_NAME (valores não reproduzidos)
- Permissões do GITHUB_TOKEN: id-token: write para OIDC no job image e contents: write no job gitops para o commit do robô na main
- Conta AWS com provedor OIDC do GitHub e roles com trust restrita ao subject imutável da main (role do CI para push no ECR; role do self-healing com eks:DescribeCluster)
- Token fine-grained do GitHub para o repository_dispatch disparado pelo Grafana (guardado em Secret, nunca no YAML); um token de leitura para o ArgoCD só seria necessário com repositório privado
- Conta New Relic (região US) com license key de ingestão para exportar OTLP pelo gateway
- PagerDuty: serviço com integração Events API V2 (Integration Key); o trial da Fase 4 ia até 2026-11-11
- Slack: canal, Incoming Webhook e app do PagerDuty conectado ao canal
- Arquivo .env local ignorado pelo Git com chaves SaaS e tokens (D5) e variáveis TF_VAR_* sensíveis; nada versionado
- Segredos de aplicação injetados por Secret do Kubernetes criados pelo Terraform: DATABASE_URL, MASTER_KEY e SERVICE_API_KEY (contrato em gitops/SECRETS-CONTRATO.md)
- Ferramentas locais: Docker Desktop com engine Linux, Git Bash, Python 3 (launcher py), kubectl 1.34.x, kustomize 5.4.3, actionlint e shellcheck; Microsoft Edge (headless) e Pillow para o PDF do relatório; PowerPoint para renderizar o roteiro; pypdfium2 para revisar PDFs; Lens opcional
- Actions de terceiros: aquasecurity/trivy-action fixada por SHA, golangci-lint-action@v9, aws-actions/configure-aws-credentials@v4 e amazon-ecr-login@v2

### Passos que ficaram manuais na Fase 4 (a eliminar na Fase 5)

- Schemas dos RDS aplicados à mão com pod psql descartável (kubectl run ... postgres:16-alpine ... < services/<svc>/db/init.sql); não existe Job de schema (GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md)
- Seed manual: POST /admin/keys com a MASTER_KEY, gravação da SERVICE_API_KEY no evaluation-service-secret (kubectl create --dry-run | apply), rollout restart do evaluation e criação da flag e da regra PERCENTAGE 100
- Gerador de tráfego criado à mão (kubectl run trafego, curl em laço) para fazer o alerta disparar
- Ativação da falha controlada por curl em POST /admin/fault (manual por desenho; o restart é automático)
- Port-forwards manuais para ArgoCD, Grafana e evaluation (não há Ingress)
- Ensaio local de traces (scripts/test-observability.sh, gate de 19 spans) e exportação ao New Relic (scripts/test-observability-newrelic.sh) rodados só na máquina local
- Prints capturados à mão no navegador, salvos em docs/evidencias/entrada-local/, revisados (segredos cobertos) e movidos para a pasta datada
- Regenerar relatório e roteiro rodando os geradores à mão (py -3.14 -B .../build_relatorio.py; build_guia_unico.py)
- Gravação e upload do vídeo pelo usuário; video_url ainda pendente em dados-entrega.json; submissão no canal da FIAP feita pelo usuário
- Sincronizar a dev com a main depois dos commits de tag do robô; PR e merge executados com autorização explícita
- Atualização manual, a cada sessão, do LOG, PENDENCIAS, DOSSIE, DECISOES e CLAUDE.md, com snapshot em _ARQUIVO_MORTO e de-para
- Contas SaaS e tokens criados pelo usuário seguindo os guias em 02_TRABALHO

### Dúvidas levantadas pela leitura (histórico)

- Na Fase 5, mantemos a política D-018 (documentos públicos sem citar Claude/Codex nem IDs internos) e os commits sem trailer Co-Authored-By de assistente, como em todos os commits da Fase 4? Ou os commits passam a levar o trailer?
- O diário da Fase 5 recomeça a numeração (D-001, P-001, F-001) e cita o que vier da Fase 4 com prefixo F4- (como a Fase 4 fez com F3-)? Ou prefere outra convenção?
- A Fase 4 não tem AGENTS.md: o Codex lia 00_COLAB_IA/LEIA-PRIMEIRO.md e o .claude/CLAUDE.md. Quer um ponteiro próprio para o Codex na raiz do repositório da Fase 5?
- Quem são os participantes da Fase 5 (nomes, RMs e usernames para o relatório)? O PDF com RMs pode ser publicado no repositório, como na Fase 4 (D-025)?
- O repositório da Fase 5 será público desde o início ou privado até a entrega? Isso muda o token do ArgoCD e o que pode ser commitado.

<a id="cruzamento"></a>
## Cruzamento dos 47 obrigatórios

Esforço: P (pequeno), M (médio), G (grande). A coluna de pendência cita as DU-xx originais; veja a resolução no início.

### REQ-OBR-01 — Regra de Ouro: aplicar as Fases 1–4 ao novo ecossistema (esforço P)

- **Camada:** Transversal: rastreio no C0 e fechamento no C10
- **Base na Fase 4:** Repositório da Fase 4 como um todo: terraform/, gitops/, .github/workflows/, observability/, services/*/telemetry.*, scripts/; 00_COLAB_IA/DECISOES.md (herança F3-*)
- **Trabalho novo:** Matriz 'disciplina das Fases 1–4 → artefato e evidência na Fase 5' (Docker, Kubernetes, Terraform, CI/CD, DevSecOps, GitOps, observabilidade, APM, resposta a incidentes), mantida em 00_COLAB_IA e reproduzida no relatório. Conteúdo próprio das Fases 1 e 2: não encontrado nos arquivos lidos (a Fase 4 já carrega a herança da Fase 3 com prefixo F3-). O esforço real está distribuído nos REQ-OBR-05 a 14.
- **Pendência na leitura:** nenhuma

### REQ-OBR-02 — Zero deploy manual via kubectl (esforço M)

- **Camada:** C4 — GitOps e deploy (ArgoCD), com C3
- **Base na Fase 4:** .github/workflows/_ci-go.yml e _ci-python.yml (job gitops: kustomize edit set image + commit [skip ci] com laço de 5 tentativas); terraform/k8s/argocd.tf (Application com prune/selfHeal/retry); gitops/overlays/prod/kustomization.yaml
- **Trabalho novo:** Substituir os passos manuais da Fase 4 descritos em 00_COLAB_IA/02_TRABALHO/GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md (schema por 'kubectl run psql', Secret por 'kubectl apply', pod de tráfego por 'kubectl run', falha por 'kubectl exec'): schema dos bancos por Job/initContainer versionado, gerador de tráfego como Deployment no Git e nenhum Secret aplicado à mão (os serviços da Fase 5 não têm chave de serviço). Documentar os únicos usos de kubectl aceitos (leitura e port-forward).
- **Pendência na leitura:** DU-10 (como ativar a falha da demonstração sem kubectl exec)

### REQ-OBR-03 — Zero infraestrutura clicada no console (esforço M)

- **Camada:** C2 — Infraestrutura como Código (raiz bootstrap)
- **Base na Fase 4:** terraform/backend.tf e terraform/backend.hcl.example (backend S3 parcial com encrypt e use_lockfile); terraform/modules/iam-ci/main.tf (provedor OIDC criado ou lido); terraform/imports.tf apenas como referência do que não repetir
- **Trabalho novo:** Nova raiz terraform/bootstrap com estado local ignorado pelo Git: bucket de estado (versionamento, bloqueio público, SSE, policy só TLS, tags) e provedor OIDC do GitHub. ECR, roles e policies do CI nascem direto no Terraform, sem criar no console e importar depois como na Fase 4. Inventário pós-apply cruzando a listagem por tag com o state. Contas SaaS (New Relic, PagerDuty, Slack) documentadas como configuração fora da nuvem.
- **Pendência na leitura:** DU-03 (bootstrap e destino do provedor OIDC já existente) e DU-01 (conta)

### REQ-OBR-04 — Zero voo cego: monitoramento profundo dos 3 serviços (esforço M)

- **Camada:** C5 — Observabilidade e APM (instrumentação no C1)
- **Base na Fase 4:** services/flag-service/telemetry.py; services/auth-service/telemetry.go; gitops/observability/values/otel-gateway.yaml e otel-agent.yaml; gitops/observability/grafana/dashboards/togglemaster-overview.json
- **Trabalho novo:** Instrumentar os 3 serviços (traces OTLP e logs JSON com trace_id/span_id); dashboard de visão geral da SolidaryTech (RPS, taxa de 5xx e p95 por serviço; CPU/memória de nós e Pods do novo namespace; logs do Loki); recomendado ao menos um alerta de 5xx por serviço, para nenhum serviço ficar sem vigilância.
- **Pendência na leitura:** DU-07 (APM e conta)

### REQ-OBR-05 — Dockerfiles otimizados para os 3 serviços (esforço M)

- **Camada:** C1 — Serviços e contêineres
- **Base na Fase 4:** services/auth-service/Dockerfile (Go multi-stage golang:1.25-alpine → alpine:3.24, binário estático, usuário não root); services/flag-service/Dockerfile (python:3.12-slim multi-stage com wheels, usuário app, exec gunicorn); services/*/.dockerignore
- **Trabalho novo:** Dockerfile e .dockerignore para donation (porta 8082), ngo (8081, com libpq) e volunteer (8083, sem libpq). Pré-requisitos: gerar e versionar o go.sum (inexistente), fixar dependências que quebram o build (Werkzeug com Flask 2.2.2) e zerar CVE CRITICAL no Trivy. Registrar o critério de 'otimizado' adotado (Q-19): multi-stage, imagem mínima, não root, sem CRITICAL.
- **Pendência na leitura:** DU-05 (atualizar dependências do código do coordenador)

### REQ-OBR-06 — Kubernetes gerenciado (EKS) (esforço M)

- **Camada:** C2 — Infraestrutura como Código (cluster) e C4 — GitOps e deploy (implantação)
- **Base na Fase 4:** terraform/modules/eks/main.tf (cluster, node group, OIDC do cluster, addons); terraform/cluster/main.tf, variables.tf e data.tf; terraform/k8s/storageclass.tf
- **Trabalho novo:** EKS em versão de suporte padrão no dia do apply (a 1.34 da Fase 4 sai do suporte padrão em 2026-12-01/02, segundo os arquivos) com upgrade_policy STANDARD; node group dimensionado pela cota de vCPU; namespace próprio com os 3 serviços Ready. EKS e não AKS/GKE porque o código depende de SQS e DynamoDB (Q-17).
- **Pendência na leitura:** DU-01 (conta e cota) e DU-02 (região)

### REQ-OBR-07 — Terraform provisiona cluster, bancos, mensageria e rede (esforço G)

- **Camada:** C2 — Infraestrutura como Código (Terraform)
- **Base na Fase 4:** terraform/main.tf (módulo VPC da comunidade ~> 5.0); terraform/modules/ecr, messaging, rds, eks, irsa e iam-ci; terraform/cluster/*; terraform/k8s/*; terraform/README.md
- **Trabalho novo:** Adaptar as raízes (chaves phase5/prod/*, nome do projeto): 3 ECR; fila SQS Standard das doações com DLQ; tabela DynamoDB SolidaryTechVolunteers com hash_key volunteer_id (String), pois o módulo da Fase 4 usa event_id; RDS PostgreSQL 16 para ngo_db e donation_db pelo mapa do módulo rds; IRSA reescrito (donation: sqs:SendMessage na fila; volunteer: PutItem e Scan na tabela), pois as policies da Fase 4 são fixas em evaluation/analytics; Secrets DATABASE_URL na camada k8s; ElastiCache fora (nenhum serviço usa cache).
- **Pendência na leitura:** DU-01 e DU-02; ADR técnico sem bloqueio: 2 instâncias RDS (reuso direto do módulo; a conta da Fase 4 aceitou 2) ou 1 instância com 2 bancos (exige criar o segundo banco por SQL)

### REQ-OBR-08 — CI/CD automatizado que executa testes (esforço G)

- **Camada:** C3 — CI/CD DevSecOps (testes escritos no C1)
- **Base na Fase 4:** .github/workflows/_ci-go.yml (go build + go test -count=1); .github/workflows/_ci-python.yml (pytest só se houver tests/); .github/workflows/flag-service.yml (chamador fino); .github/workflows/compose-integration.yml; scripts/test-compose.sh; docker-compose.integration.yaml (Moto 5.2.2 por digest); scripts/integration/bootstrap-aws.py; services/auth-service/handlers_test.go (go-sqlmock); services/flag-service/tests/
- **Trabalho novo:** Escrever testes do zero, pois o código recebido não tem nenhum: Go com sqlmock para POST/GET /donations e publicação SQS simulada; Python com pytest e mocks do pool psycopg2 (ngo) e do DynamoDB/Moto (volunteer), definindo as variáveis antes do import porque os módulos encerram o processo se faltar configuração. Tornar o pytest obrigatório no reutilizável (falhar sem testes). Ensaio Compose com PostgreSQL + Moto (SQS e DynamoDB) e test-flow.py reescrito para ONGs, doações e voluntários.
- **Pendência na leitura:** DU-05 (nível de teste: unitários + integração Compose/Moto)

### REQ-OBR-09 — Scans SAST e SCA no pipeline (esforço P)

- **Camada:** C3 — CI/CD DevSecOps
- **Base na Fase 4:** .github/workflows/_ci-go.yml (golangci-lint v2.13.2, gosec v2.29.0 -severity high, Trivy fs CRITICAL com action pinada por SHA); .github/workflows/_ci-python.yml (flake8, pylint com .pylintrc, bandit -ll, Trivy fs e de imagem); .trivyignore (política de exceção nominal e datada); .pylintrc
- **Trabalho novo:** Aplicar SAST (gosec, bandit) e SCA (Trivy fs e de imagem) nos 3 serviços; começar o .trivyignore sem exceções; fixar as versões de bandit e pytest (soltas na Fase 4); declarar permissions mínimas nos jobs de verificação, que na Fase 4 herdavam id-token/contents write do chamador.
- **Pendência na leitura:** DU-05 (corrigir dependência ou registrar exceção quando o Trivy reprovar)

### REQ-OBR-10 — Build da imagem dentro do pipeline (esforço M)

- **Camada:** C3 — CI/CD DevSecOps (ECR e role OIDC vêm do C2)
- **Base na Fase 4:** .github/workflows/_ci-go.yml e _ci-python.yml (jobs image-scan e image: build, Trivy CRITICAL, OIDC, push com tag v1.0.0-<sha7>); terraform/modules/ecr/main.tf; terraform/modules/iam-ci/main.tf e tests/trust.tftest.hcl
- **Trabalho novo:** 3 repositórios ECR pelo Terraform; role OIDC do CI com subject do novo repositório (IDs numéricos do owner e do repo, ref da main) e push só nesses ECR; atualizar os 10 casos do terraform test; cadastrar as Repository Variables AWS_REGION, ECR_REGISTRY e AWS_ROLE_ARN (nenhum segredo AWS no GitHub).
- **Pendência na leitura:** DU-04 (repositório definitivo e visibilidade)

### REQ-OBR-11 — GitOps com ArgoCD (esforço M)

- **Camada:** C4 — GitOps e deploy (ArgoCD)
- **Base na Fase 4:** terraform/k8s/argocd.tf (helm_release do chart 7.7.23 com imagem v2.13.9 e apply em 2 etapas); gitops/base/kustomization.yaml; gitops/overlays/prod/kustomization.yaml; gitops/README.md
- **Trabalho novo:** Application da SolidaryTech apontando para o overlay prod do novo repositório; base Kustomize dos 3 serviços (Deployment, Service, ConfigMap); reconferir versão do chart e CVE; retirar o ignoreDifferences de HPA, já que não haverá HPA no escopo obrigatório. ArgoCD (e não FluxCD) porque a demo pede deploy 'via ArgoCD' (Q-04).
- **Pendência na leitura:** DU-04 (público ou privado define o token de leitura do ArgoCD)

### REQ-OBR-12 — Stack de observabilidade completa rodando (esforço M)

- **Camada:** C5 — Observabilidade e APM
- **Base na Fase 4:** gitops/observability/applications/*.yaml (kube-prometheus-stack 92.17.1, loki 7.5.0, opentelemetry-collector 0.178.2 como gateway e agente); gitops/observability/values/*.yaml; gitops/observability/kustomization.yaml; terraform/k8s/observability.tf
- **Trabalho novo:** Trocar o repoURL do $values (fixo no tech-challenge-04) e os nomes togglemaster-*; revisar versões; ajustar requests/limits ao novo cluster; manter Prometheus, Grafana, Loki e OTel Collector (leitura conservadora da Q-03).
- **Pendência na leitura:** nenhuma

### REQ-OBR-13 — APM com Distributed Tracing (esforço G)

- **Camada:** C1 — Serviços e contêineres (código) e C5 — Observabilidade e APM (exportação)
- **Base na Fase 4:** services/auth-service/telemetry.go; services/flag-service/telemetry.py; services/evaluation-service/sqs.go (span PRODUCER e traceparent em MessageAttributes); services/analytics-service/app.py (traced_operation para DynamoDB); gitops/observability/values/otel-gateway.yaml (exporter otlp_http/newrelic); docker-compose.otel.yaml e docker-compose.newrelic.yaml; scripts/integration/test-traces.py
- **Trabalho novo:** Go: otelhttp, spans de PostgreSQL com QueryRowContext/QueryContext e span PRODUCER na SQS com contexto propagado (hoje 'go a.sendNotificationEvent(d)' roda sem contexto). ngo: cursor_factory no pool, porque o RealDictCursor passado em conn.cursor() apaga os spans SQL. volunteer: spans manuais de PutItem e Scan. Reescrever a prova automatizada de traces, que na Fase 4 exige 5 serviços e um consumidor SQS que não existem aqui.
- **Pendência na leitura:** DU-06 (trace entre serviços) e DU-07 (APM e conta)

### REQ-OBR-14 — Automação de resposta a incidentes (alerta → incidente → ação) (esforço M)

- **Camada:** C8 — ITSM e AIOps
- **Base na Fase 4:** gitops/observability/grafana/alerting/rules.yaml, policies.yaml, contactpoints.yaml e templates.yaml; .github/workflows/self-healing.yml; scripts/self-healing/restart.sh e test-restart.sh; gitops/base/self-healing-rbac.yaml; terraform/cluster/self-healing.tf; terraform/modules/iam-ci/main.tf (role de self-healing); terraform/k8s/observability.tf (Secret grafana-notificacoes)
- **Trabalho novo:** Regra do donation-service no lugar da FlagService5xxAlto; renomear contact points, templates, receivers e o grupo Kubernetes; ajustar allowlist, options do workflow_dispatch, resourceNames do RBAC e testes; URL do repository_dispatch do novo repositório; kubectl fixado na versão do novo EKS; falha controlada para o ensaio. Obrigatoriedade marcada [INCERTO] no mapa (Q-09), tratada como obrigatória.
- **Pendência na leitura:** DU-07 (PagerDuty e Slack) e DU-10 (falha controlada e escopo do self-healing)

### REQ-OBR-15 — No mínimo 2 SLIs do donation-service (esforço M)

- **Camada:** C6 — SRE
- **Base na Fase 4:** gitops/observability/values/otel-gateway.yaml (conector span_metrics: traces_span_metrics_calls_total e traces_span_metrics_duration_milliseconds_bucket); consultas de taxa de 5xx e p95 em gitops/observability/grafana/dashboards/togglemaster-overview.json
- **Trabalho novo:** SLI de disponibilidade (proporção de spans SERVER do donation-service sem erro, com /health já excluído no Collector) e SLI de latência (proporção abaixo de um limiar), com recording rules e documento formal; conferir se o limiar coincide com um bucket do histograma (hoje 5 ms a 5 s).
- **Pendência na leitura:** DU-08 (metas, limiar e janela)

### REQ-OBR-16 — Um SLO para cada SLI (esforço P)

- **Camada:** C6 — SRE
- **Base na Fase 4:** nenhum
- **Trabalho novo:** A Fase 4 não tem SLO nem error budget. Definir uma meta por SLI, com janela declarada e política simples de error budget, versionadas em docs e refletidas nas regras e no painel.
- **Pendência na leitura:** DU-08

### REQ-OBR-17 — Dashboard SRE exclusivo de SLOs e Error Budget (esforço M)

- **Camada:** C6 — SRE
- **Base na Fase 4:** gitops/observability/kustomization.yaml (ConfigMap com label grafana_dashboard lido pelo sidecar); gitops/observability/grafana/dashboards/togglemaster-overview.json (padrão); scripts/gitops/check-grafana.py e test-check-grafana.py; gitops/observability/values/kube-prometheus-stack.yaml (retenção 2d/4GiB, PVC de 5Gi)
- **Trabalho novo:** Novo dashboard JSON só de SLO para o donation-service: SLI x meta, error budget restante e consumo; ajustar retenção e disco do Prometheus à janela adotada; incluir o painel no check-grafana.py. Golden Metrics no mesmo painel conforme a leitura adotada para a Q-18.
- **Pendência na leitura:** DU-08 (janela do SLO)

### REQ-OBR-18 — Relatório: como observabilidade e automações reduzem o MTTR (esforço M)

- **Camada:** C6 — SRE (medição) e C10 — Entregáveis (relatório)
- **Base na Fase 4:** docs/evidencias/README.md (linha do tempo com horário e fonte); docs/relatorio/dados-entrega.json; docs/ARQUITETURA.md (cadeia alerta → incidente → recuperação)
- **Trabalho novo:** Linha do tempo medida do incidente simulado da SolidaryTech (falha, detecção, notificação, mitigação, recuperação), coletada no Loki, na execução do GitHub Actions e no Slack como na Fase 4, com texto mostrando como cada automação encurta uma etapa; recomendado medir também uma execução sem automação como linha de base (SUG-07).
- **Pendência na leitura:** nenhuma

### REQ-OBR-19 — Política de tags obrigatórias no Terraform (esforço M)

- **Camada:** C2 — Infraestrutura como Código (código) e C7 — FinOps (verificação)
- **Base na Fase 4:** terraform/providers.tf e terraform/variables.tf (default_tags; hoje project=fiap e phase=4, em minúsculas), repetidos em terraform/cluster/ e terraform/k8s/; terraform/k8s/storageclass.tf
- **Trabalho novo:** default_tags Project=SolidaryTech, Environment=Production e CostCenter=NGO-Core, com a caixa exata, nas 4 raízes; launch template com tag_specifications para instâncias e volumes do node group; tags nos volumes do EBS CSI (parâmetros da StorageClass, que na Fase 4 não tem tags); ativação das tags de alocação de custo pelo Terraform (confirmar o recurso no apply); script que lista recursos sem as 3 tags e registro das exceções que não aceitam tag (Q-10, leitura adotada: exatamente as três; extras são bônus).
- **Pendência na leitura:** nenhuma

### REQ-OBR-20 — Rightsizing de requests e limits via GitOps (esforço M)

- **Camada:** C7 — FinOps (sobre C4 e C5)
- **Base na Fase 4:** gitops/base/*/deployment.yaml (requests/limits por contêiner); painéis de CPU e memória por Pod em gitops/observability/grafana/dashboards/togglemaster-overview.json
- **Trabalho novo:** Valores iniciais conservadores; carga sintética contínua; medir uso por Pod no Prometheus (p95 de CPU e working set); ajustar requests/limits por PR no GitOps com justificativa numérica; evidência antes/depois aplicada pelo ArgoCD.
- **Pendência na leitura:** nenhuma

### REQ-OBR-21 — Forecast de custos mensais (esforço M)

- **Camada:** C7 — FinOps
- **Base na Fase 4:** 00_COLAB_IA/02_TRABALHO/PREPARACAO_B3_2026-11-04_v01.md e PREPARACAO_B3_2026-11-05_v02.md (estimativa pela Price List: US$ 0,409/h com tudo ligado em us-east-2); 00_COLAB_IA/02_TRABALHO/AUDITORIA_CUSTOS_AWS_2026-11-13_v01.md (custo real por serviço; arquivo local não versionado)
- **Trabalho novo:** Projeção mensal da arquitetura de produção em operação contínua, por componente (EKS, nós, NAT, RDS, SQS, DynamoDB, S3/backups, volumes, transferência), com preço, fonte e data; cenários normal, pico de campanha e com DR; validação de cima para baixo com custos reais por tag quando existirem.
- **Pendência na leitura:** Horizonte, base e moeda do Forecast (Q-16); conversão para reais só com taxa citada e datada

### REQ-OBR-22 — Pelo menos uma recomendação de otimização nativa (esforço P)

- **Camada:** C7 — FinOps
- **Base na Fase 4:** 00_COLAB_IA/02_TRABALHO/AUDITORIA_CUSTOS_AWS_2026-11-13_v01.md (EC2 foi o maior item: US$ 14,97 de 33,55; arquivo local); 00_COLAB_IA/02_TRABALHO/ANALISE_COMPLETA_FASE4_2026-10-31_v01.md (TFC-04 sem autoscaler, TFC-12 NAT)
- **Trabalho novo:** Ao menos uma recomendação com economia estimada. Candidatas coerentes com os dados: Savings Plans, Spot ou Graviton para os nós (maior custo); endpoints de gateway da VPC para S3 e DynamoDB, reduzindo tráfego pelo NAT; Query em GSI no lugar do Scan do volunteer-service.
- **Pendência na leitura:** Qual recomendação apresentar (não bloqueia)

### REQ-OBR-23 — IA do APM detectando anomalias (esforço M)

- **Camada:** C8 — ITSM e AIOps
- **Base na Fase 4:** gitops/observability/values/otel-gateway.yaml (exportação OTLP ao New Relic; a Fase 4 não tem AIOps)
- **Trabalho novo:** Ativar a detecção de anomalias/Applied Intelligence para o donation-service (preferir configuração como código, se o plano permitir), manter tráfego estável antes da gravação para o aprendizado e registrar a ativação e, se possível, uma anomalia detectada no ensaio. Não encontrado nos arquivos se o recurso cobre entidades OpenTelemetry nem se está no plano gratuito/educacional (Q-11).
- **Pendência na leitura:** DU-07 (conta e recursos do plano do APM)

### REQ-OBR-24 — Ciclo de vida do incidente desenhado (esforço M)

- **Camada:** C8 — ITSM e AIOps
- **Base na Fase 4:** docs/ARQUITETURA.md (cadeia alerta → incidente → recuperação com horários do ensaio); observability/README.md (runbook do FlagService5xxAlto); docs/evidencias/README.md
- **Trabalho novo:** Diagrama e texto do ciclo da SolidaryTech: detecção (IA do APM ou alerta) → registro e classificação → notificação (PagerDuty e Slack) → mitigação automática → resolução → PostMortem → comunicação à diretoria e às ONGs, com papéis, severidades e modelo de PostMortem. Framework: SRE com ITIL 4 como complemento (Q-12).
- **Pendência na leitura:** nenhuma

### REQ-OBR-25 — Documento executivo de PCN (esforço M)

- **Camada:** C9 — Disaster Recovery e PCN
- **Base na Fase 4:** nenhum
- **Trabalho novo:** PCN executivo: processo crítico (receber doações), impactos, RTO e RPO, estratégia de DR, papéis, comunicação, testes e justificativa das regiões, inclusive o tema LGPD (SUG-16).
- **Pendência na leitura:** DU-09 (estratégia e metas) e DU-02 (regiões)

### REQ-OBR-26 — RTO e RPO dos dados de doação (esforço P)

- **Camada:** C9 — Disaster Recovery e PCN
- **Base na Fase 4:** terraform/modules/rds/main.tf e terraform/modules/rds/variables.tf (backup_retention_period=1, skip_final_snapshot=true, deletion_protection=false)
- **Trabalho novo:** Definir RTO e RPO coerentes com onde o dado mora (donation_db no RDS, fora do cluster, protegido por backups automáticos/PITR) e confirmá-los com o ensaio de restore cronometrado.
- **Pendência na leitura:** DU-09 (valores-alvo, definidos pelo usuário)

### REQ-OBR-27 — Estratégia de DR implementada (Opção A ou B) (esforço G)

- **Camada:** C9 — Disaster Recovery e PCN
- **Base na Fase 4:** gitops/observability/applications/*.yaml (padrão de Application Helm multi-source com sync waves); terraform/modules/irsa/main.tf (padrão IRSA); terraform/modules/rds/main.tf (parâmetros de backup); terraform/k8s/argocd.tf
- **Trabalho novo:** Recomendada a Opção A: bucket de backup na região secundária e role IRSA do Velero no Terraform; Velero por Application do ArgoCD com Schedules no Git; backups automáticos do RDS com retenção e cópia na região secundária, porque o Velero não protege o RDS (SUG-14); runbook e ensaio de restore cronometrado. A Opção B exigiria um segundo ambiente completo e uma orquestração de '1 comando' que a Fase 4 não tem.
- **Pendência na leitura:** DU-09 (Opção A ou B) e DU-02 (região secundária)

### REQ-OBR-28 — Regra de avaliação: mostrar tudo funcionando (esforço M)

- **Camada:** C10 — Entregáveis (matriz iniciada no C0)
- **Base na Fase 4:** docs/evidencias/README.md (índice de prints com obrigatórios marcados e registros com horário e fonte); docs/evidencias/entrada-local/LEIA-ME.md; 00_COLAB_IA/02_TRABALHO/MATRIZ_REQUISITOS_FASE4_2026-10-28_v01.json
- **Trabalho novo:** Matriz requisito → evidência (repositório, vídeo, relatório) para os 47 obrigatórios, atualizada ao fim de cada camada, com prints datados e revisados sem segredos.
- **Pendência na leitura:** nenhuma

### REQ-OBR-29 — Repositório: Terraform completo com tags FinOps (esforço P)

- **Camada:** C2 — Infraestrutura como Código (Terraform)
- **Base na Fase 4:** terraform/** e .github/workflows/terraform-check.yml
- **Trabalho novo:** Versionar todo o IaC, inclusive o bootstrap e os arquivos .example, e manter fmt, validate e terraform test no CI cobrindo as 4 raízes, junto da checagem de tags.
- **Pendência na leitura:** nenhuma

### REQ-OBR-30 — Repositório: manifestos YAML com requests/limits (esforço P)

- **Camada:** C4 — GitOps e deploy (ArgoCD), ajustados no C7
- **Base na Fase 4:** gitops/base/*/deployment.yaml
- **Trabalho novo:** requests/limits em todos os contêineres do namespace da aplicação (3 serviços, Job de schema e gerador de tráfego), com checagem no GitOps Check.
- **Pendência na leitura:** nenhuma

### REQ-OBR-31 — Repositório: pipelines com DevSecOps (esforço P)

- **Camada:** C3 — CI/CD DevSecOps
- **Base na Fase 4:** .github/workflows/*; docs/CI-CD.md
- **Trabalho novo:** Versionar os workflows adaptados e reescrever docs/CI-CD.md para os 3 serviços.
- **Pendência na leitura:** nenhuma

### REQ-OBR-32 — Vídeo de até 20 minutos (esforço G)

- **Camada:** C10 — Entregáveis
- **Base na Fase 4:** docs/gravacao/README.md (cenas cronometradas); docs/gravacao/roteiro-conteudo.json; docs/gravacao/PASSO_A_PASSO_POR_CENA.md; docs/gravacao/COMANDOS.md; 00_COLAB_IA/02_TRABALHO/entrega-gravacao-2026-11-11_v03/build_guia_unico.py
- **Trabalho novo:** Roteiro em blocos por frente com o pitch e a demo embutida, ensaiado com cronômetro e fechado abaixo de 20:00; o roteiro da Fase 4 usava 21 minutos para um limite de 25.
- **Pendência na leitura:** Q-01 (leitura adotada: um vídeo de 15 a 20 minutos com a demo) e DU-11 (quem grava e onde hospedar)

### REQ-OBR-33 — Pitch executivo para a diretoria (esforço M)

- **Camada:** C10 — Entregáveis
- **Base na Fase 4:** docs/gravacao/roteiro-conteudo.json (estrutura de cena: tela, ações, fala, confira, fonte)
- **Trabalho novo:** Narrativa para a diretoria da ONG: arquitetura, PCN (RTO e RPO em minutos), Forecast e recomendações traduzidos em linguagem de negócio.
- **Pendência na leitura:** nenhuma

### REQ-OBR-34 — Demo: CI/CD rodando e deploy via ArgoCD (esforço P)

- **Camada:** C10 — Entregáveis (sobre C3 e C4)
- **Base na Fase 4:** docs/gravacao/COMANDOS.md; docs/evidencias/2026-11-09/05-argocd.png (formato de evidência)
- **Trabalho novo:** Cena: PR ou push → jobs verdes → imagem no ECR → commit do robô no overlay → sync do ArgoCD.
- **Pendência na leitura:** nenhuma

### REQ-OBR-35 — Demo: Terraform rodando ou recursos por tag (esforço P)

- **Camada:** C10 — Entregáveis (sobre C2 e C7)
- **Base na Fase 4:** 00_COLAB_IA/02_TRABALHO/GUIA_DEPLOY_E_GRAVACAO_2026-11-09_v01.md (plan salvo e apply do próprio plano)
- **Trabalho novo:** Cena: plan e apply de uma mudança pequena e listagem dos recursos filtrados por Project=SolidaryTech.
- **Pendência na leitura:** nenhuma

### REQ-OBR-36 — Demo: traces no APM e alertas configurados (esforço P)

- **Camada:** C10 — Entregáveis (sobre C5 e C8)
- **Base na Fase 4:** docs/gravacao/COMANDOS.md (trace, Loki, falha controlada); docs/evidencias/2026-11-09/02-trace-mapa.png, 02-trace-spans.png e 07-grafana-firing.png (formato)
- **Trabalho novo:** Cena: trace do donation-service no APM com spans de PostgreSQL e SQS e as regras de alerta configuradas.
- **Pendência na leitura:** nenhuma

### REQ-OBR-37 — Demo: Dashboard SRE com Golden Metrics e SLOs calculados (esforço P)

- **Camada:** C10 — Entregáveis (sobre C6)
- **Base na Fase 4:** docs/gravacao/PASSO_A_PASSO_POR_CENA.md (formato de cena)
- **Trabalho novo:** Cena: painel SRE com SLIs, metas e error budget calculados sobre tráfego real.
- **Pendência na leitura:** nenhuma

### REQ-OBR-38 — Demo: Backup/DR em ação (esforço M)

- **Camada:** C10 — Entregáveis (sobre C9)
- **Base na Fase 4:** docs/gravacao/PASSO_A_PASSO_POR_CENA.md (formato de cena)
- **Trabalho novo:** Cena ensaiada: backup do Velero concluído no bucket da região secundária, restore de teste e ponto de restauração do RDS; planejar a interação com o selfHeal do ArgoCD para o restore ficar visível.
- **Pendência na leitura:** DU-09 (inclui a Q-13: se é preciso restore real)

### REQ-OBR-39 — Relatório de entrega em PDF (esforço M)

- **Camada:** C10 — Entregáveis
- **Base na Fase 4:** 00_COLAB_IA/02_TRABALHO/entrega-relatorio-2026-11-11_v03/build_relatorio.py (JSON + prints → HTML → PDF pelo Edge headless); docs/relatorio/README.md; docs/relatorio/dados-entrega.json
- **Trabalho novo:** Adaptar o gerador às seções exigidas (SRE, FinOps, Segurança e DR, ITSM/AIOps) com as evidências visuais obrigatórias.
- **Pendência na leitura:** nenhuma

### REQ-OBR-40 — Relatório: nomes, RMs e usernames (esforço P)

- **Camada:** C10 — Entregáveis
- **Base na Fase 4:** docs/relatorio/dados-entrega.json (campo de participantes)
- **Trabalho novo:** Preencher com os dados fornecidos pelo usuário, sem inventar.
- **Pendência na leitura:** DU-11 (integrantes, plataforma dos usernames, Q-15, e publicação do PDF com RMs)

### REQ-OBR-41 — Relatório: links do repositório e do vídeo (esforço P)

- **Camada:** C10 — Entregáveis
- **Base na Fase 4:** docs/relatorio/dados-entrega.json (repositório e video_url)
- **Trabalho novo:** Incluir o link do repositório e, após o upload, o do vídeo; regenerar o PDF.
- **Pendência na leitura:** DU-04 (URL definitiva) e DU-11 (hospedagem do vídeo)

### REQ-OBR-42 — Seção SRE: SLI, SLO e SLA formais (esforço M)

- **Camada:** C10 — Entregáveis (conteúdo do C6)
- **Base na Fase 4:** nenhum
- **Trabalho novo:** Definição formal de SLI, SLO e SLA do serviço de doações; o SLA com as ONGs precisa de meta, forma de medição, exclusões e consequência (Q-14).
- **Pendência na leitura:** DU-08 (termos do SLA)

### REQ-OBR-43 — Seção FinOps: Forecast e evidência das tags (esforço M)

- **Camada:** C10 — Entregáveis (conteúdo do C7)
- **Base na Fase 4:** 00_COLAB_IA/02_TRABALHO/PREPARACAO_B3_2026-11-05_v02.md (método de estimativa); 00_COLAB_IA/02_TRABALHO/AUDITORIA_CUSTOS_AWS_2026-11-13_v01.md (auditoria de custo real; arquivo local)
- **Trabalho novo:** Forecast mensal com cenários e evidências das tags (listagem por tag e custo agrupado por tag), com prints datados.
- **Pendência na leitura:** nenhuma

### REQ-OBR-44 — Seção Segurança e DR: PCN e estratégia (esforço P)

- **Camada:** C10 — Entregáveis (conteúdo do C9)
- **Base na Fase 4:** nenhum
- **Trabalho novo:** PCN com RTO e RPO e explicação da estratégia de DR, acompanhados das evidências do ensaio de restore.
- **Pendência na leitura:** DU-09

### REQ-OBR-45 — Seção ITSM/AIOps: ciclo de vida de incidentes (esforço P)

- **Camada:** C10 — Entregáveis (conteúdo do C8)
- **Base na Fase 4:** docs/ARQUITETURA.md (diagrama dos sinais e da cadeia de incidente)
- **Trabalho novo:** Desenho do ciclo de vida do incidente acompanhado da evidência do ensaio.
- **Pendência na leitura:** nenhuma

### REQ-OBR-46 — Desenvolvimento em grupo (esforço P)

- **Camada:** C0 — Fundação do repositório e colaboração
- **Base na Fase 4:** 00_COLAB_IA/LEIA-PRIMEIRO.md (protocolo de colaboração entre agentes)
- **Trabalho novo:** Registrar integrantes e papéis; o protocolo Claude↔Codex organiza os agentes e não substitui o grupo humano. Obrigatoriedade marcada [INCERTO] no mapa (Q-05).
- **Pendência na leitura:** DU-11 (composição do grupo)

### REQ-OBR-47 — Entrega dentro do prazo (esforço P)

- **Camada:** C0 — Fundação (calendário) e C10 — Entregáveis (submissão)
- **Base na Fase 4:** 00_COLAB_IA/PENDENCIAS_E_PROXIMOS_PASSOS.md (calendário e checklist do pedido vigente)
- **Trabalho novo:** Calendário reverso a partir da data de entrega, com janelas de ambiente ligado (custo), de aprendizado da IA do APM e de ensaio da gravação.
- **Pendência na leitura:** DU-11 (data, hora e canal: Q-06 e Q-07)

<a id="riscos"></a>
## Riscos consolidados

- Créditos e custo: a referência da Fase 4 é US$ 0,409/h com tudo ligado (Price List, us-east-2, 2026-11-04), e o consumo real foi US$ 33,55 de 09 a 12/11 (EC2 14,97; EKS 7,83; EC2-Other/NAT/EBS 5,40; RDS 3,31), contra cerca de US$ 126 de crédito em 2026-11-13. Ligado 24x7, um ambiente parecido esgota os créditos em cerca de duas semanas. Budgets ficaram fora do escopo obrigatório; se forem criados, devem nascer no Terraform (na Fase 4 o Budget foi criado por CLI).
- EKS: a versão 1.34 sai do suporte padrão em 2026-12-01/02 (data citada nos arquivos da Fase 4) e o código não tem upgrade_policy; no suporte estendido o control plane passa de US$ 0,10/h para US$ 0,60/h. O kubectl fixado no self-healing (v1.34.13) precisa acompanhar a nova versão.
- Capacidade: cota de 5 vCPU On-Demand na conta da Fase 4 (no máximo 2 nós m7i-flex.large) e memória já apertada com a observabilidade (TFC-01); Velero e o gerador de tráfego aumentam a carga, e sem Cluster Autoscaler os nós não escalam sozinhos.
- NAT obrigatório: o exemplo da base da Fase 4 vem com enable_nat_gateway=false; sem NAT, os nós privados não baixam imagens (ImagePullBackOff) e telemetria e alertas não chegam a New Relic, PagerDuty, Slack e GitHub.
- O código recebido quebra o pipeline copiado: o donation-service não tem go.sum e declara go 1.21 (na Fase 4 o upgrade do x/crypto levou a diretiva a 1.25, e o OTel Go 1.46.0 rodou com go 1.25); golang.org/x/crypto v0.20.0 tende a reprovar no gate CRITICAL do Trivy; Flask 2.2.2 sem Werkzeug fixado tende a falhar no import (a Fase 4 fixou Werkzeug<3); não há Dockerfile nem teste. Confirmar com build e Trivy locais antes de ligar os gates.
- Spans SQL somem sem erro no ngo-service: o cursor_factory=RealDictCursor passado em conn.cursor() descarta o cursor instrumentado (lição D-016 da Fase 4); a factory precisa ir para o pool.
- donation-service: a publicação na SQS roda em goroutine sem contexto e a resposta é 201 mesmo se o evento falhar, o que o SLI HTTP não enxerga; a integração com a SQS é desligada em silêncio se faltar AWS_SQS_URL ou AWS_REGION; não há tratamento de SIGTERM. Conferir no deploy a linha de log que confirma a integração ativa.
- volunteer-service usa us-east-1 por padrão quando AWS_REGION falta: com a primária em us-east-2, o serviço sobe normalmente e só falha nas requisições.
- Tráfego sintético contínuo faz a tabela donations crescer, e o GET /donations (sem paginação, devolve todas as linhas) fica mais lento com o tempo, distorcendo o SLI de latência. O volunteer-service faz Scan filtrado por ngo_id (custo e latência crescem com a tabela) e converte ngo_id fora do try (payload inválido vira 500). Calibrar o gerador com payloads válidos e escolher bem as rotas do SLI.
- Schema sem kubectl manual: por padrão, o Kustomize e o ArgoCD não leem arquivos fora da pasta da kustomization (services/*/db/init.sql). O init.sql do ngo-service tem INSERT de seed sem ON CONFLICT com e-mail UNIQUE: um Job reexecutado falha, ou o psql termina com código 0 mascarando o erro se ON_ERROR_STOP não estiver ligado.
- Passos manuais da Fase 4 conflitam com o REQ-OBR-02 (psql por 'kubectl run', Secret por 'kubectl apply', pod de tráfego por 'kubectl run', falha por 'kubectl exec'), e recursos criados fora do Terraform conflitam com o REQ-OBR-03 (bucket de estado, OIDC, role e policy do CI, 5 ECR, Budget). terraform/imports.tf não deve ser reaproveitado e, na mesma conta, o OIDC antigo continua existindo.
- Primeiro apply da camada k8s: exige duas etapas (-target=helm_release.argocd e depois o completo) porque o kubernetes_manifest valida o CRD no plan; o mesmo vale para qualquer CRD novo declarado pelo Terraform.
- OIDC com subject imutável (owner@ID/repo@ID e ref da main): um formato errado dá AccessDenied no primeiro push na main; conferir o sub emitido para o novo repositório antes. O repository_dispatch só aciona workflows da branch padrão.
- Tags: as default_tags não chegam às instâncias EC2 do node group sem launch template nem aos volumes EBS criados pelo CSI (a StorageClass da Fase 4 não tem tags); a chave é sensível a maiúsculas (a Fase 4 usou project e phase). Ativar cedo as tags de alocação de custo para a evidência no Cost Explorer; o tempo de propagação não foi encontrado nos arquivos e precisa ser conferido.
- SLO e ambiente efêmero: a retenção do Prometheus de 2d/4GiB em PVC de 5Gi e o destroy/recreate impedem medir uma janela real de 30 dias; com noDataState OK e metrics_expiration de 5m, uma regra de proporção não dispara sem tráfego (inferência da Fase 4, não testada).
- AIOps é o item de maior incerteza: a detecção de anomalias precisa aprender o normal com tráfego estável (SUG-12), o que choca com o ambiente efêmero; a Fase 4 não tem nada de AIOps; não foi encontrado nos arquivos se a IA do New Relic cobre entidades OpenTelemetry nem se está disponível no plano gratuito ou educacional (Q-11).
- PagerDuty: o trial de 14 dias da Fase 4 ia até 2026-11-11, e no plano Free o efeito sobre a Events API ficou como INCERTO. Planejar o trial para cobrir ensaio e gravação.
- Armadilhas do Grafana já vividas na Fase 4: $$values chega literal às annotations; segredo com cara de número quebra o provisionamento (Integration Key do PagerDuty); DatasourceError herda selfheal=true, então a rota precisa exigir alertname; o webhook exige authorization_scheme e payload template; o cooldown de 600 s pede intervalo entre ensaio e gravação.
- Segredos em texto puro no state e nos *.tfplan (senhas do RDS, DATABASE_URL, chaves SaaS): restringir o acesso ao bucket de estado. Não copiar da pasta da Fase 4 backend.hcl, terraform.tfvars, .terraform/, *.tfplan nem arquivos locais que contêm o ID da conta (ex.: 00_COLAB_IA/02_TRABALHO/ENCERRAMENTO_AWS_2026-11-12_v01.md).
- Repositório: o tech-challenge-05 ainda não tem .gitignore (criar antes de qualquer terraform init ou .env), e README.md e services/ ainda não estão versionados. Se o repositório for público, tudo o que for commitado é público: na Fase 4 o overlay expôs o ID da conta (registro do ECR, URL da SQS, ARNs IRSA), e a referência de imagem no overlay continuará contendo o registro do ECR.
- DR: o Velero não protege o PostgreSQL do RDS (SUG-14); snapshots EBS feitos pelo Velero ficam na região do cluster, e a cópia para fora exige backup de sistema de arquivos ou cópia de snapshot (confirmar na implementação); o selfHeal do ArgoCD recria a partir do Git o que for apagado e pode mascarar a demo de restore; com skip_final_snapshot=true e deletion_protection=false (padrão da Fase 4), um destroy remove a instância e, por padrão, os backups automáticos que não forem retidos ou replicados (conferir delete_automated_backups).
- A Opção B do DR pede '1 comando', mas a orquestração herdada tem 3 raízes, publicação de imagens pelo CI, preenchimento manual do overlay e apply da camada k8s em 2 etapas; exigiria reprojeto e um segundo EKS com cota na outra região.
- Destroy: os PVCs (Prometheus, Loki e o que o Velero restaurar) geram volumes EBS que podem ficar órfãos. Remover antes as Applications pai do ArgoCD (finalizers), conferir PVC, PV e EBS antes de derrubar o cluster e o CSI e sempre usar plan -destroy -out.
- Tracing: sem chamadas entre serviços nem consumidor SQS, os traces serão por serviço; a prova automatizada da Fase 4 (scripts/integration/test-traces.py exige 5 serviços) precisa ser reescrita; há risco de o avaliador esperar um trace atravessando serviços (DU-06).
- Gate do Trivy (CRITICAL com ignore-unfixed false): já bloqueou a Fase 4 por CVEs sem correção na imagem base (perl-base no python:3.12-slim), com exceções cuja revisão venceu em 2026-10-15. As imagens base estão por tag, não por digest; a pinagem das actions é inconsistente (só trivy e self-healing por SHA) e o kustomize do job gitops é baixado sem checksum.
- Colaboração entre agentes: limites de uso interromperam subagentes na Fase 4 (D-007), então cada artefato e o estado parcial precisam ir para o LOG antes de parar. Comentários herdados desatualizados (ESO, 'sem testes', IDs F3-, custos da conta da Fase 3) enganam o próximo agente e gerariam afirmações falsas no relatório. Registro de agente não é prova: conferir contra código, Git e execuções.
- Ambiente Windows: no Git Bash, 'python' pode cair no atalho da Microsoft Store; o PowerShell 5.1 não tem &&; scripts .sh precisam de eol=lf (.gitattributes); caminhos podem exigir MSYS_NO_PATHCONV.
- Vídeo e prazo: o limite é de 20 min (a Fase 4 planejou 21 min para um limite de 25), e pipeline e sync levam minutos, então é preciso gravar trechos preparados e ensaiar com cronômetro. Data, hora e canal de entrega não constam no enunciado (Q-06 e Q-07).
- Partida dos serviços: ngo e donation encerram o processo se o banco não responder na inicialização, e o volunteer encerra se faltar AWS_DYNAMODB_TABLE (CrashLoopBackOff até RDS, Secret e ConfigMap existirem); sem o schema aplicado, as rotas respondem 500.
- A cópia em services/ não foi conferida contra o repositório-fonte do coordenador (sem acesso à rede nesta análise). O README do coordenador descreve as pastas na raiz, mas aqui elas estão em services/: documentar o mapeamento para os agentes.
