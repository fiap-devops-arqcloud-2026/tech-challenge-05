# Raiz `base` — rede, imagens, mensageria e identidades do CI

TL;DR: a parte barata e de vida longa da infraestrutura: VPC com sub-redes públicas, privadas e de banco, os três repositórios ECR, a fila SQS com DLQ, a tabela DynamoDB e as roles OIDC do GitHub Actions. O estado fica em `phase5/prod/base.tfstate`; as raízes `cluster` e `k8s` e o CI leem as saídas daqui. O único custo fixo relevante é o NAT Gateway, que `enable_nat_gateway` liga e desliga.

## O que esta raiz cria

| Peça | Nome | Por quê |
|---|---|---|
| VPC (módulo da comunidade `terraform-aws-modules/vpc/aws`) | `solidarytech-vpc`, 10.0.0.0/16 em us-east-2a e us-east-2b | Sub-redes privadas (nós do EKS), públicas (NAT) e de banco (RDS, com DB subnet group `solidarytech-db`); um NAT só; tags de descoberta do Kubernetes |
| Endpoints de gateway | S3 e DynamoDB | Gratuitos: o tráfego das sub-redes privadas para esses serviços (inclusive as camadas das imagens do ECR) não paga o processamento do NAT |
| ECR (`../modules/ecr`) | `solidarytech/ngo-service`, `solidarytech/donation-service`, `solidarytech/volunteer-service` | Tag imutável, scan no push, AES256, `force_delete` e só as 10 imagens mais recentes |
| SQS (`../modules/messaging`) | `solidary-donations` e `solidary-donations-dlq` | Fila Standard cifrada; depois de 5 leituras sem exclusão, a mensagem vai para a DLQ, que guarda 14 dias |
| DynamoDB (`../modules/messaging`) | `SolidaryTechVolunteers` (chave `volunteer_id`, String) | Cobrança por requisição, criptografia com a chave gerenciada e recuperação para um ponto no tempo (PITR) |
| IAM (`../modules/iam-ci`) | `solidarytech-github-ci` e `solidarytech-github-self-healing` | Assumidas só pela branch `main` deste repositório (subject OIDC exato, com os IDs imutáveis). O CI publica só nos 3 repositórios ECR; o self-healing só chama `eks:DescribeCluster` no cluster `solidarytech-eks` |

Todos os recursos recebem as tags `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core` e `ManagedBy=Terraform` pelo `default_tags` do provider.

O provedor OIDC do GitHub **não** é criado aqui: ele é um por conta, pertence à raiz `bootstrap` e é só lido por data source.

## Antes de aplicar

1. A raiz `bootstrap` aplicada: ela cria o bucket de estado e o provedor OIDC do GitHub. Sem o provedor, o plan desta raiz falha logo no início.
2. Credenciais da conta certa no terminal. O provider recusa outra conta (`allowed_account_ids`).
3. Os arquivos locais preenchidos. Eles são ignorados pelo Git:

```bash
# Modelo do backend: troque o sentinela pelo bucket de estado (output state_bucket_name da bootstrap)
cp terraform/base/backend.hcl.example terraform/base/backend.hcl

# Modelo das variáveis: troque a conta fictícia pelo ID real
cp terraform/base/terraform.tfvars.example terraform/base/terraform.tfvars
```

## Aplicar

Sempre com plano salvo: o que é aplicado é exatamente o que foi revisado.

```bash
# Inicializa com o backend S3 (bucket e região vêm do backend.hcl)
terraform -chdir=terraform/base init -backend-config=backend.hcl

# Gera o plano e o salva em arquivo, para revisão
terraform -chdir=terraform/base plan -out=base.tfplan

# Aplica exatamente o plano revisado
terraform -chdir=terraform/base apply base.tfplan

# Mostra as saídas para as próximas raízes e para o CI
terraform -chdir=terraform/base output
```

## Saídas

| Saída | Quem usa |
|---|---|
| `aws_region`, `eks_cluster_name` | `cluster`, `k8s` e CI |
| `vpc_id`, `vpc_cidr_block`, `private_subnet_ids`, `public_subnet_ids`, `database_subnet_group_name` | `cluster` (EKS e RDS) |
| `ecr_registry`, `ecr_repository_urls` | CI (login e push das imagens) e GitOps |
| `sqs_queue_name`, `sqs_queue_url`, `sqs_queue_arn`, `sqs_dlq_arn` | `cluster` (IRSA do donation-service) e `k8s` (ConfigMap) |
| `dynamodb_table_name`, `dynamodb_table_arn` | `cluster` (IRSA do volunteer-service) e `k8s` (ConfigMap) |
| `ci_role_arn`, `self_healing_role_arn` | CI; `cluster` (access entry do self-healing) |

Nenhuma saída é segredo. URLs e ARNs carregam o ID da conta, por isso são lidos do estado e não escritos em arquivo versionado.

## Custo e destruição

- **NAT Gateway:** cobrado por hora e por GB, mesmo ocioso. Com o cluster no ar ele é obrigatório (sem ele, os nós não baixam imagens). Se a base ficar de pé sem cluster, `enable_nat_gateway = false` no `terraform.tfvars` e um novo plano salvo cortam esse custo.
- **Ordem do destroy:** `k8s` → `cluster` → `base`. Os repositórios ECR são apagados mesmo com imagens (`force_delete`), e a tabela não tem proteção contra exclusão: o ambiente é efêmero.

```bash
# Plano de destruição salvo, para revisão
terraform -chdir=terraform/base plan -destroy -out=base-destroy.tfplan

# Aplica exatamente o plano de destruição revisado
terraform -chdir=terraform/base apply base-destroy.tfplan
```

## Validação offline (sem AWS)

```bash
# Formatação de todo o Terraform
terraform fmt -check -recursive terraform

# Raiz base: baixa providers e módulos sem configurar o backend (não acessa o S3)
terraform -chdir=terraform/base init -backend=false -input=false

# Raiz base: confere sintaxe, tipos e referências
terraform -chdir=terraform/base validate

# Raiz base: teste da composição com provider simulado (mock_provider)
terraform -chdir=terraform/base test

# Módulo iam-ci: baixa o provider sem backend
terraform -chdir=terraform/modules/iam-ci init -backend=false -input=false

# Módulo iam-ci: testes da trust e das policies (command = plan, sem acesso à AWS)
terraform -chdir=terraform/modules/iam-ci test

# Módulo ecr: baixa o provider sem backend
terraform -chdir=terraform/modules/ecr init -backend=false -input=false

# Módulo ecr: testes dos repositórios (command = plan, sem acesso à AWS)
terraform -chdir=terraform/modules/ecr test

# Módulo messaging: baixa o provider sem backend
terraform -chdir=terraform/modules/messaging init -backend=false -input=false

# Módulo messaging: testes da fila e da tabela (command = plan, sem acesso à AWS)
terraform -chdir=terraform/modules/messaging test
```

O teste do `iam-ci` é o mais importante: ele prova que só a branch `main` deste repositório, com o audience do STS, assume as roles, que entradas com curinga são recusadas e que cada role recebe só a permissão do seu trabalho. Validação offline não prova acesso à conta nem o funcionamento na AWS.
