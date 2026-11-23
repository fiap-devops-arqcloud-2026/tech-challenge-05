# Raiz `cluster`: EKS, RDS e identidades dos Pods

TL;DR: cria o cluster EKS com o node group, o PostgreSQL gerenciado e as roles IRSA dos serviços. É a raiz que cobra por hora: sobe no início de cada janela de trabalho e é destruída no fim, sempre com plano salvo. Lê a raiz `base` por `terraform_remote_state` e é lida pela raiz `k8s`.

## O que cria

| Peça | Detalhe |
|---|---|
| Cluster EKS | `solidarytech-eks` (nome publicado pela base), Kubernetes 1.37, `upgrade_policy` STANDARD, endpoint público e privado, acesso só por access entries (`authentication_mode = "API"`), sem logs do control plane |
| Node group | `solidarytech-nodes`: 2 nós `m7i-flex.large` ON_DEMAND (AL2023), mínimo 2 e máximo 3, nas sub-redes privadas |
| Launch template dos nós | disco raiz gp3 cifrado de 20 GiB, IMDSv2 obrigatório (limite de saltos 2), tags obrigatórias nas instâncias e nos volumes, **sem** security groups |
| Addons gerenciados | `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver` (com role IRSA) e `metrics-server`, na versão mais recente compatível |
| Provedor OIDC do cluster | base do IRSA |
| RDS PostgreSQL | `solidarytech-postgres`: PostgreSQL 17, `db.t4g.micro`, gp3 de 20 GiB cifrado, uma AZ, privado, backups com PITR (7 dias por padrão; ver a retenção no plano gratuito abaixo), usuário mestre `solidary_admin` com senha gerada pelo Terraform |
| Firewall do RDS | entrada 5432 só do security group do cluster; nenhuma regra de saída |
| Roles IRSA | `donation-service`: `sqs:SendMessage` na fila; `volunteer-service`: `dynamodb:PutItem` e `dynamodb:Scan` na tabela; `ngo-service` sem role |
| Access entry do self-healing | role do workflow mapeada ao grupo Kubernetes `solidarytech-self-healing`, sem access policy da AWS (as permissões vêm do RBAC do GitOps) |

Os bancos `ngo_db` e `donation_db` e os usuários de cada serviço não nascem aqui: o Job de schema os cria com o usuário mestre.

## Pré-requisitos

- Raízes `bootstrap` e `base` aplicadas, com o NAT Gateway ligado na base (`enable_nat_gateway = true`). Sem NAT, os nós não baixam imagens; o plano desta raiz avisa quando a VPC não tem NAT disponível.
- Credenciais da conta do projeto no terminal (perfil da AWS CLI).
- Terraform 1.11 ou mais novo.

## Como aplicar

```bash
# Entra na pasta desta raiz, a partir da raiz do repositório
cd terraform/cluster

# Cria o backend.hcl local (ignorado pelo Git); troque os sentinelas pelo bucket e pela região reais
cp backend.hcl.example backend.hcl

# Cria o terraform.tfvars local (ignorado pelo Git); troque os valores fictícios pelos reais
cp terraform.tfvars.example terraform.tfvars

# Conecta ao backend S3 (bucket e região do backend.hcl; a chave é fixa)
terraform init -backend-config=backend.hcl

# Gera o plano salvo para revisão; nada é criado ainda
terraform plan -out=cluster.tfplan

# Aplica exatamente o plano revisado
terraform apply cluster.tfplan
```

## Retenção de backup do RDS no plano gratuito

A conta está no plano gratuito (FREE) da AWS. A documentação oficial da AWS
não publica limite de retenção de backup para esse plano: a API do RDS aceita
de 0 a 35 dias, e o código usa 7. Mesmo assim, há relatos públicos de contas
no plano gratuito em que o `CreateDBInstance` recusa mais de 1 dia, e a Fase 4
usou 1 dia nesta mesma conta. O resultado só aparece no apply.

**Sintoma.** O apply termina com erro em `module.rds.aws_db_instance.this`,
com uma mensagem como `FreeTierRestrictionError: The specified backup
retention period exceeds the maximum available to free tier customers`. O
banco não depende do EKS: o restante (cluster, nós, addons, IRSA) segue e fica
no estado, e só o RDS e as saídas dele faltam. Sem elas, a raiz `k8s` não
roda.

**Troca para 1 dia.** Gere um novo plano com a retenção de 1 dia; ele deve
criar só o que faltou:

```bash
# Gera o plano salvo com 1 dia de retenção (a linha de comando vence o terraform.tfvars)
terraform plan -var=db_backup_retention_days=1 -out=cluster.tfplan

# Aplica exatamente o plano revisado
terraform apply cluster.tfplan
```

Depois disso, grave `db_backup_retention_days = 1` no `terraform.tfvars`: sem
isso, o próximo plano tentaria voltar a 7 dias e repetiria o erro numa
modificação do banco. Com 1 dia, a restauração para um ponto no tempo (PITR)
cobre só as últimas 24 horas, o que vale como RPO na estratégia de DR enquanto
a conta estiver no plano gratuito; num plano pago, volte para 7.

## Usar o kubectl

Depois do apply, para usar o `kubectl` local:

```bash
# Grava o acesso ao cluster no kubeconfig local
aws eks update-kubeconfig --region us-east-2 --name "$(terraform output -raw cluster_name)"
```

## Como destruir

Primeiro a raiz `k8s`, para que o driver EBS CSI ainda exista quando os PersistentVolumeClaims forem apagados (senão os volumes EBS ficam órfãos e cobrando). Depois:

```bash
# Gera o plano de destruição para revisão
terraform plan -destroy -out=cluster-destroy.tfplan

# Destrói exatamente o que o plano mostrou
terraform apply cluster-destroy.tfplan
```

Ao fim, confira no console ou na CLI se sobrou volume EBS no estado `available` com a tag `Project=SolidaryTech`.

## Saídas (contrato com a raiz `k8s`)

`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_version`, `cluster_security_group_id`, `oidc_provider_arn`, `node_role_arn`, `rds_address`, `rds_port`, `rds_master_username`, `rds_master_password` (sensível), `irsa_role_arns` (mapa `donation-service`/`volunteer-service` → ARN) e `app_namespace`.

## Decisões que não devem regredir

- **Launch template sem security groups.** Se ele definir grupos, o EKS deixa de anexar o security group do cluster aos nós, e o RDS, que aceita só esse grupo, fica inalcançável.
- **Tags no launch template.** O node group não propaga as próprias tags para as instâncias e os volumes; sem elas, o maior custo da conta some do filtro por tag.
- **Nome do cluster vindo da base.** A policy do self-healing foi montada na base com o ARN desse nome.
- **Endpoint público aberto (`0.0.0.0/0`).** O self-healing roda em runners hospedados do GitHub, com IPs variáveis; a API continua exigindo credencial AWS e access entry.
- **IMDS com limite de saltos 2 (custo aceito).** É o padrão do EKS e funcionou na Fase 4, mas deixa qualquer Pod sem `hostNetwork` (os serviços, o gerador de tráfego, o Job de schema) obter a credencial da role do nó, mesmo tendo a própria role IRSA. Essa role carrega a `AmazonEKS_CNI_Policy` (interfaces de rede da conta) e o pull de qualquer repositório ECR da conta (`AmazonEC2ContainerRegistryPullOnly`). Endurecimento possível, numa janela própria e com teste: role IRSA para o `aws-node` no addon `vpc-cni` e a CNI fora da role do nó.
- **Senha mestra no estado, sem Secrets Manager.** O estado fica no bucket cifrado e de acesso restrito; a raiz `k8s` transforma a senha em Secret do Kubernetes.
- **Ambiente efêmero.** Sem proteção contra exclusão no cluster e no banco, sem snapshot final; os backups automáticos são apagados com a instância.

## Validação offline (sem credenciais)

```bash
# Instala os providers sem acessar o backend S3
terraform init -backend=false

# Confere sintaxe, tipos e referências
terraform validate

# Testes com provider falso: composição, saídas e proteções desta raiz
terraform test
```

Os módulos `../modules/eks`, `../modules/rds` e `../modules/irsa` têm testes próprios, rodados da mesma forma dentro de cada pasta.
