# Desenho da C2 — Terraform da SolidaryTech

TL;DR: Quatro raízes (`bootstrap`, `base`, `cluster`, `k8s`) com estado próprio no S3, ligadas por `terraform_remote_state`, e módulos adaptados da Fase 4. Este documento é o contrato entre as raízes: nomes de variáveis, outputs, recursos e convenções. Quem implementa uma raiz segue este contrato; mudança de contrato entra aqui primeiro.

Última atualização: 2026-11-20, Claude.

Fontes: [leitura da conta](LEITURA_AWS_C2_2026-11-20_v01.md), [mapeamento da Fase 4](MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md), DECISOES D-003, D-005, D-008, D-012, D-014, D-015 e D-016. Base de código: `tech-challenge-04/terraform/` (somente leitura).

## Retificação — 2026-11-21 (implementação e ajustes do orquestrador)

O código já faz, além do texto abaixo:
- **Bucket de estado** no namespace regional da conta: `bucket_namespace = "account-regional"` e nome `<project_name>-tfstate-<conta>-<região>-an` (formato da documentação do provider v6.73.0), com `lifecycle { prevent_destroy = true }`. O destroy final do bucket exige remover essa linha de propósito.
- **Role dos nós** com `AmazonEC2ContainerRegistryPullOnly` no lugar de `AmazonEC2ContainerRegistryReadOnly`.
- **Nome do cluster** lido do output `eks_cluster_name` da base: o ARN da policy do self-healing, montado na base, sempre bate com o cluster real.
- **ApplicationSet** desligado com `applicationSet.replicas = 0`: o chart argo-cd 10.18.2 não tem `applicationSet.enabled`.
- **Application** com o finalizer `resources-finalizer.argocd.argoproj.io`, e o `helm_release` do `argocd-apps` com `wait`: no destroy da `k8s`, o ArgoCD apaga os recursos da aplicação (e os volumes) antes de ser desinstalado.
- **Senha mestre** do RDS lida pela `k8s` com `sensitive()`: o `terraform_remote_state` não preserva a marca de sensível dos outputs.
- **Testes** em todas as 10 pastas (4 raízes e 6 módulos), não só no `iam-ci`: a seção 8 vale para todas.
- **Retenção de backup do RDS**: 7 dias pedem confirmação no plano FREE (a Fase 4 usou 1 dia nesta conta); o resultado da revisão fica no README do `cluster`.

## Retificação — 2026-11-23 (revisão adversarial concluída)

- Revisão em três frentes (segurança e IAM; correção na AWS; FinOps, requisitos e docs) com verificador: 18 achados (1 ALTA, 3 MÉDIAS, 14 BAIXAS), 15 confirmados e corrigidos, 1 incerto. Os testes passaram de 83 para 88 cenários.
- **Retenção do RDS (incerto):** a documentação oficial só diz "0 a 35 dias" e não cita limite para o plano FREE. Fica 7; se o apply recusar (`FreeTierRestrictionError`), o README do `cluster` descreve a troca para 1 dia. Com 1 dia o PITR continua; a janela de volta cai para 24 h.
- **Validação do `state_bucket`** em `cluster` e `k8s` passou a exigir o sufixo `-<conta>-<state_region>-an`: só o bucket da conta esperada é aceito.
- **Tags de alocação de custo:** ativar até 24 h antes da primeira janela do cluster (o backfill existe), para o Budget filtrado por tag ter dados.
- **Addons do EKS 1.37** conferidos por leitura em 2026-11-23, em us-east-2: vpc-cni v1.23.3-eksbuild.2, coredns v1.14.7-eksbuild.35, kube-proxy v1.37.0-eksbuild.39, aws-ebs-csi-driver v1.68.1-eksbuild.1 e metrics-server v0.9.1-eksbuild.2.
- **Riscos que só o primeiro apply revela:** o Budget usa `CostFilters`/`CostTypes`, marcados como obsoletos na API (o provider 6.73 ainda os usa); não se sabe se a API aceita filtrar por uma tag ainda não ativada.
- **Endurecimentos opcionais, fora do escopo atual:** role IRSA para o `aws-node`, com a policy do CNI fora da role do nó; route table própria para as sub-redes de banco; AppProject próprio no ArgoCD.

## 1. Convenções para todas as raízes

- **Terraform** `required_version = ">= 1.11.0, < 2.0.0"` (o `use_lockfile` do backend S3 exige 1.11+; local: 1.16.0).
- **Providers** (versões atuais conferidas em 2026-11-20): `hashicorp/aws ~> 6.73`, `hashicorp/kubernetes ~> 3.5`, `hashicorp/helm ~> 3.3` (sintaxe v3: `kubernetes = { ... }` e `set = [ ... ]` como atributos), `hashicorp/random ~> 3.9`. Módulo `terraform-aws-modules/vpc/aws ~> 6.8`.
- **Lock files** `.terraform.lock.hcl` versionados em cada raiz e em módulos com testes, gerados pelo `terraform init -backend=false` (os hashes `zh:` vindos do registro cobrem todas as plataformas; o CI Linux acrescenta o seu `h1:` sozinho).
- **Provider AWS** em todas as raízes: `region = var.aws_region`, `allowed_account_ids = [var.expected_aws_account_id]` e `default_tags { tags = local.required_tags }`.
- **Tags obrigatórias** (D-015), iguais em todas as raízes:
  ```hcl
  locals {
    required_tags = {
      Project     = "SolidaryTech"
      Environment = "Production"
      CostCenter  = "NGO-Core"
      ManagedBy   = "Terraform"
    }
  }
  ```
  Recursos que não herdam `default_tags` (instâncias e volumes do node group, volumes EBS do CSI) recebem as tags explicitamente.
- **Variáveis comuns** em todas as raízes:
  - `project_name` (string, padrão `"solidarytech"`, validação `^[a-z][a-z0-9-]{2,20}$`);
  - `aws_region` (padrão `"us-east-2"`);
  - `expected_aws_account_id` (sem padrão, validação `^[0-9]{12}$`): vem do tfvars local ou de `TF_VAR_expected_aws_account_id`, nunca do Git.
- **Backend** S3 parcial nas raízes `base`, `cluster` e `k8s` (e no `bootstrap` depois da migração):
  ```hcl
  terraform {
    backend "s3" {
      key          = "phase5/prod/<raiz>.tfstate"
      encrypt      = true
      use_lockfile = true
    }
  }
  ```
  `bucket` e `region` ficam no `backend.hcl` local (ignorado pelo Git); cada raiz tem um `backend.hcl.example` com valores sentinela.
- **Remote state**: `cluster` e `k8s` recebem `state_bucket` e `state_region` (sem padrão) e leem `phase5/prod/base.tfstate` e `phase5/prod/cluster.tfstate`.
- **Arquivos por raiz**: `versions.tf` (terraform + required_providers + backend), `providers.tf`, `variables.tf`, `main.tf` (ou arquivos por assunto), `outputs.tf`, `terraform.tfvars.example`, `backend.hcl.example` e `README.md` curto.
- **Comentários em português**, com acentos, explicando o porquê (cabeçalho por arquivo e comentário nos trechos não óbvios). Documentos públicos sem nomes de agentes nem IDs internos (D-011); citar decisões pelo assunto, não pelo número.
- **Segurança**: nada de segredo em código ou exemplo; variáveis sensíveis com `sensitive = true`; senhas por `random_password` com caracteres seguros para URL (`special = false` ou `override_special = "-_"`).
- **Custo**: ambiente efêmero. Nada de `deletion_protection`, snapshot final ou `prevent_destroy`, exceto no bucket de estado (`force_destroy = false`).
- **Proibido** para quem implementa: `terraform plan` ou `apply` com backend, e qualquer comando AWS de escrita. Permitido e esperado: `terraform fmt`, `init -backend=false`, `validate` e `test` com `mock_provider`.

## 2. Nomes dos recursos

| Recurso | Nome |
|---|---|
| Bucket de estado | `${project_name}-tfstate-${account_id}-${aws_region}` |
| Budget | `${project_name}-mensal` |
| VPC | `${project_name}-vpc` (10.0.0.0/16; us-east-2a e us-east-2b) |
| ECR | `${project_name}/ngo-service`, `${project_name}/donation-service`, `${project_name}/volunteer-service` |
| Fila SQS e DLQ | `solidary-donations` e `solidary-donations-dlq` (nome do README do coordenador) |
| Tabela DynamoDB | `SolidaryTechVolunteers` (PK `volunteer_id`, String) |
| Role do CI | `${project_name}-github-ci` |
| Role do self-healing | `${project_name}-github-self-healing` |
| Cluster EKS | `${project_name}-eks` |
| Node group | `${project_name}-nodes` |
| RDS | `${project_name}-postgres` |
| Namespace da aplicação | `solidarytech` |
| ServiceAccounts | `ngo-service`, `donation-service`, `volunteer-service` (namespace `solidarytech`) |

## 3. Raiz `terraform/bootstrap/`

Cria o que as outras raízes precisam antes de existir. Primeiro apply com estado local (arquivo `backend_override.tf`, ignorado pelo Git por `*_override.tf`, com `terraform { backend "local" {} }`); depois o override sai e `terraform init -migrate-state -backend-config=backend.hcl` leva o estado para `phase5/prod/bootstrap.tfstate`. O README da raiz explica os dois passos, com um comentário acima de cada comando.

Recursos:
- `data "aws_caller_identity"` e `data "aws_partition"`.
- Bucket de estado: `aws_s3_bucket` (`force_destroy = false`), `aws_s3_bucket_versioning` (Enabled), `aws_s3_bucket_server_side_encryption_configuration` (AES256), `aws_s3_bucket_public_access_block` (os quatro bloqueios), `aws_s3_bucket_ownership_controls` (BucketOwnerEnforced), `aws_s3_bucket_policy` negando `aws:SecureTransport = false`, `aws_s3_bucket_lifecycle_configuration` (versões não correntes expiram em 90 dias; uploads incompletos abortados em 7 dias).
- Provedor OIDC do GitHub: `aws_iam_openid_connect_provider "github"` com `url = "https://token.actions.githubusercontent.com"`, `client_id_list = ["sts.amazonaws.com"]`, `thumbprint_list = var.github_oidc_thumbprints` (padrão `["ab9d0263244dd0326eb67015705a667e79cfe998"]`, o valor da conta; comentar que a AWS valida o GitHub pela própria cadeia de CAs e que o valor só evita diferença no import).
- Import condicional, no mesmo padrão já validado num apply da Fase 4 (`for_each` de zero ou um elemento):
  ```hcl
  import {
    for_each = var.import_existing_github_oidc_provider ? toset(["github"]) : toset([])
    to       = aws_iam_openid_connect_provider.github
    id       = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  }
  ```
  `import_existing_github_oidc_provider` tem padrão `true` (a conta do projeto já tem o provedor); em conta nova, `false` cria o provedor.
- `aws_budgets_budget "monthly"`: COST, MONTHLY, `limit_amount = var.monthly_budget_usd` (padrão `"50"`), `cost_filter { name = "TagKeyValue"; values = ["user:Project$SolidaryTech"] }`, `cost_types { include_credit = false; include_refund = false }` (senão os créditos zeram o custo e o alerta nunca dispara), notificações ACTUAL a 50%, 80% e 100% e FORECASTED a 100%, para `var.budget_alert_emails` (lista, sem padrão, vinda do tfvars local).
- `aws_ce_cost_allocation_tag` para `Project`, `Environment` e `CostCenter`, com `count`/`for_each` controlado por `var.activate_cost_allocation_tags` (padrão `false`). Comentar: a AWS só aceita ativar uma tag depois que ela aparece no faturamento (até 24 h depois do primeiro recurso com a tag); a ativação é feita na C7, e até lá o filtro por tag do Budget fica sem dados.

Outputs: `state_bucket_name`, `state_bucket_region`, `github_oidc_provider_arn`, `budget_name`.

## 4. Raiz `terraform/base/`

Rede, registro de imagens, mensageria, tabela e identidades do CI. Custo fixo baixo (o NAT é o item caro; `enable_nat_gateway` liga e desliga).

Variáveis próprias: `vpc_cidr` (`"10.0.0.0/16"`), `azs` (`["us-east-2a", "us-east-2b"]`), `enable_nat_gateway` (`true`), `services` (`["ngo-service", "donation-service", "volunteer-service"]`), `sqs_queue_name` (`"solidary-donations"`), `dynamodb_table_name` (`"SolidaryTechVolunteers"`), `eks_cluster_name` (`"solidarytech-eks"`, usado para montar o ARN previsível do cluster na policy do self-healing), `github_repository` (`"fiap-devops-arqcloud-2026/tech-challenge-05"`), `github_repository_owner_id` (`287716251`), `github_repository_id` (`1454212968`), `github_deploy_branch` (`"main"`).

Recursos e módulos:
- `module "vpc"` (comunidade, `~> 6.8`): sub-redes públicas, privadas e de banco (`database_subnets`, `create_database_subnet_group = true`) nas duas AZs; `single_nat_gateway = true`; DNS habilitado; tags de descoberta do EKS (`kubernetes.io/role/elb = 1` nas públicas, `kubernetes.io/role/internal-elb = 1` nas privadas).
- Endpoints de gateway (gratuitos) para S3 e DynamoDB nas route tables privadas: o tráfego para esses serviços não paga NAT (argumento de FinOps).
- `module "ecr"` (`modules/ecr`, da Fase 4): um repositório por serviço; `image_tag_mutability = "IMMUTABLE"` (o CI publica só tags com o SHA); `scan_on_push = true`; AES256; `force_delete = true`; lifecycle mantendo as 10 imagens mais recentes.
- `module "messaging"` (`modules/messaging`, da Fase 4): fila Standard com `sqs_managed_sse_enabled = true` e redrive para a DLQ (`maxReceiveCount = 5`, DLQ com retenção de 14 dias); tabela DynamoDB `PAY_PER_REQUEST` com SSE e `point_in_time_recovery { enabled = true }` (DR, D-005).
- `module "iam_ci"` (`modules/iam-ci`, da Fase 4, sem a criação do provedor OIDC, que agora é do bootstrap): recebe `github_oidc_provider_arn` de `data "aws_iam_openid_connect_provider" "github" { url = "https://token.actions.githubusercontent.com" }`. Trust com `aud = sts.amazonaws.com` e `sub` exato `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>`. Role do CI com push só nos 3 ARNs de ECR (mais `ecr:GetAuthorizationToken` em `*`). Role do self-healing só com `eks:DescribeCluster` no ARN do cluster. `terraform test` da trust (adaptar `tests/trust.tftest.hcl` da Fase 4, com `mock_provider` se precisar de dados da AWS).

Outputs (nomes exatos, consumidos por `cluster`, `k8s` e pelo CI):
`aws_region`, `vpc_id`, `vpc_cidr_block`, `private_subnet_ids`, `public_subnet_ids`, `database_subnet_group_name`, `ecr_registry` (host `<conta>.dkr.ecr.<região>.amazonaws.com`), `ecr_repository_urls` (mapa serviço → URL), `sqs_queue_name`, `sqs_queue_url`, `sqs_queue_arn`, `sqs_dlq_arn`, `dynamodb_table_name`, `dynamodb_table_arn`, `ci_role_arn`, `self_healing_role_arn`, `eks_cluster_name`.

## 5. Raiz `terraform/cluster/`

EKS, banco e identidades dos Pods. É a raiz cara: destruída ao fim de cada janela.

Variáveis próprias: `state_bucket`, `state_region`, `kubernetes_version` (`"1.37"`), `node_instance_type` (`"m7i-flex.large"`), `node_desired_size` (2), `node_min_size` (2), `node_max_size` (3), `node_disk_size_gb` (20), `cluster_endpoint_public_access_cidrs` (`["0.0.0.0/0"]`, comentar que o CI do GitHub precisa alcançar a API), `db_instance_class` (`"db.t4g.micro"`), `db_engine_version` (`"17"`, só a versão maior), `db_allocated_storage_gb` (20), `db_backup_retention_days` (7), `app_namespace` (`"solidarytech"`).

Módulos:
- `module "eks"` (`modules/eks`, da Fase 4): role do control plane e dos nós; `access_config { authentication_mode = "API"; bootstrap_cluster_creator_admin_permissions = true }`; `upgrade_policy { support_type = "STANDARD" }` (evita a cobrança do suporte estendido); endpoint público e privado; sem log de control plane no CloudWatch (custo, documentado). Provedor OIDC do cluster para IRSA. Node group gerenciado ON_DEMAND, `ami_type = "AL2023_x86_64_STANDARD"`, com `launch_template` próprio: disco gp3 cifrado de `node_disk_size_gb`, IMDSv2 obrigatório (`http_tokens = "required"`) com `http_put_response_hop_limit = 2` (o padrão do EKS, que funcionou na Fase 4; o limite 1 bloquearia o acesso de Pods sem `hostNetwork` ao IMDS, de que alguns add-ons dependem; os serviços usam IRSA), `tag_specifications` de `instance` e `volume` com as tags obrigatórias (o node group não propaga tags para as instâncias, o que quebraria o custo por tag) e **sem** `vpc_security_group_ids` (se o launch template definir security groups, o EKS deixa de anexar o security group do cluster aos nós, e o RDS, que aceita só esse grupo, fica inalcançável). Addons gerenciados `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver` (com role IRSA) e `metrics-server`, com versão de `data "aws_eks_addon_version"` (`most_recent = true`).
- `module "rds"` (`modules/rds`, da Fase 4, agora com UMA instância): PostgreSQL `db_engine_version`, `db_instance_class`, gp3 de `db_allocated_storage_gb`, `storage_encrypted = true`, `multi_az = false`, `publicly_accessible = false`, `db_subnet_group_name` do base, security group aceitando 5432 só do security group do cluster EKS, `backup_retention_period = db_backup_retention_days` (PITR), `copy_tags_to_snapshot = true`, `auto_minor_version_upgrade = true`, `deletion_protection = false`, `skip_final_snapshot = true`, `apply_immediately = true`. Usuário mestre `solidary_admin` com `random_password` (24 caracteres, sem especiais). Sem `db_name`: os bancos `ngo_db` e `donation_db` e os usuários por serviço são criados pelo Job de schema da C4. Sem Secrets Manager (custo; a senha fica no estado cifrado e vira Secret do Kubernetes na raiz `k8s`).
- `module "irsa"` (`modules/irsa`, da Fase 4): uma role por ServiceAccount com condição `sub = system:serviceaccount:<ns>:<sa>` e `aud = sts.amazonaws.com`. `donation-service`: `sqs:SendMessage` no ARN da fila. `volunteer-service`: `dynamodb:PutItem` e `dynamodb:Scan` no ARN da tabela. `ngo-service` não tem role.
- `aws_eks_access_entry` para `self_healing_role_arn` com `kubernetes_groups = ["solidarytech-self-healing"]`, sem `aws_eks_access_policy_association`: as permissões vêm só do RBAC desse grupo, que fica no GitOps (C8), restrito a reiniciar os Deployments da aplicação.

Outputs (nomes exatos, consumidos por `k8s`):
`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_version`, `cluster_security_group_id`, `oidc_provider_arn`, `node_role_arn`, `rds_address`, `rds_port`, `rds_master_username`, `rds_master_password` (sensitive), `irsa_role_arns` (mapa `donation-service`/`volunteer-service` → ARN), `app_namespace`.

## 6. Raiz `terraform/k8s/`

Objetos do Kubernetes que dependem de valores da AWS (para que nenhum ID da conta precise ir para o Git) e o ArgoCD.

Variáveis próprias: `state_bucket`, `state_region`, `argocd_chart_version` (`"10.18.2"`, app v3.6.2), `argocd_apps_chart_version` (`"2.0.8"`), `gitops_repo_url` (`"https://github.com/fiap-devops-arqcloud-2026/tech-challenge-05.git"`), `gitops_revision` (`"main"`), `gitops_app_path` (`"gitops/overlays/prod"`), `enable_applications` (padrão `false`: a Application só é criada na C4, quando `gitops/` existir).

Providers `kubernetes` e `helm` autenticados por `exec` (`aws eks get-token --cluster-name ... --region ...`) com host e CA do remote state do `cluster`.

Recursos:
- `kubernetes_namespace_v1 "app"` (`solidarytech`, com labels `app.kubernetes.io/part-of = solidarytech`).
- `kubernetes_storage_class_v1 "gp3"`: padrão do cluster (`storageclass.kubernetes.io/is-default-class = "true"`), `ebs.csi.aws.com`, `type = gp3`, `encrypted = "true"`, `tagSpecification_1..4` com as tags obrigatórias, `WaitForFirstConsumer`, `Delete`, expansão permitida.
- `random_password` para os usuários de aplicação `ngo_app` e `donation_app` (24 caracteres, sem especiais).
- `kubernetes_secret_v1 "ngo_db"` (`ngo-service-db`): `DATABASE_URL = postgresql://ngo_app:<senha>@<rds_address>:<rds_port>/ngo_db?sslmode=require`.
- `kubernetes_secret_v1 "donation_db"` (`donation-service-db`): `DATABASE_URL = postgres://donation_app:<senha>@<rds_address>:<rds_port>/donation_db?sslmode=require`.
- `kubernetes_secret_v1 "db_schema"` (`db-schema`): `PGHOST`, `PGPORT`, `PGUSER` (mestre), `PGPASSWORD` (mestre), `NGO_APP_PASSWORD`, `DONATION_APP_PASSWORD` e `PGSSLMODE = require`, para o Job de schema da C4.
- `kubernetes_config_map_v1 "aws"` (`aws-endpoints`): `AWS_REGION`, `AWS_SQS_URL`, `AWS_DYNAMODB_TABLE`.
- `kubernetes_service_account_v1` para `donation-service` e `volunteer-service` com a anotação `eks.amazonaws.com/role-arn` (IRSA) e para `ngo-service` sem anotação; `automount_service_account_token = false` no `ngo-service` (ele não fala com a API do Kubernetes nem com a AWS).
- `helm_release "argocd"`: chart `argo-cd` do repositório `https://argoproj.github.io/argo-helm`, versão `argocd_chart_version`, namespace `argocd` com `create_namespace = true`, `server.service.type = ClusterIP` (acesso por port-forward), Dex desligado, recursos pequenos.
- `helm_release "argocd_apps"`: chart `argocd-apps`, versão `argocd_apps_chart_version`, `depends_on = [helm_release.argocd]`, com a Application `solidarytech` (projeto `default`, `repoURL = gitops_repo_url`, `targetRevision = gitops_revision`, `path = gitops_app_path`, destino `https://kubernetes.default.svc` no namespace `solidarytech`, `syncPolicy.automated { prune = true, selfHeal = true }`, `retry` com backoff). Só existe com `enable_applications = true`. Usar o chart de apps evita o apply em duas etapas da Fase 4 (`kubernetes_manifest` exige os CRDs já instalados no plano).

Outputs: `app_namespace`, `argocd_namespace`, `db_secret_names` (mapa), `aws_config_map_name`.

## 7. Ordem de aplicação (para o README de `terraform/`)

1. `bootstrap` (estado local) → migrar o estado para o S3.
2. `base`.
3. Publicação das imagens pelo CI (C3) — antes do `k8s` com `enable_applications = true`.
4. `cluster`.
5. `k8s` (um apply só).
6. Destroy na ordem inversa: `k8s` → `cluster` → `base` (com `enable_nat_gateway = false` antes, se a base ficar). O `bootstrap` só é destruído no fim do projeto (esvaziar o bucket antes).

Todo apply e destroy: `terraform plan -out=<raiz>.tfplan` → revisão → `terraform apply <raiz>.tfplan`, com autorização do usuário.

## 8. Verificação esperada (offline)

- `terraform fmt -check -recursive terraform/` sem diferenças.
- Em cada raiz: `terraform init -backend=false` e `terraform validate` verdes.
- `terraform test` do `modules/iam-ci` verde (trust aceita só `main` do repositório certo, com o `aud` certo; policy do CI só nos 3 ECR; self-healing só `eks:DescribeCluster`).
- Nenhum valor de conta, e-mail ou segredo nos arquivos versionados (`bash scripts/security-check.sh`).
