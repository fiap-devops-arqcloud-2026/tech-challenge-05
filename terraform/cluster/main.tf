# =================================================================
# COMPOSIÇÃO DA RAIZ CLUSTER — EKS, banco e identidades dos Pods
# =================================================================
# Este arquivo não cria recurso direto: chama os módulos e liga a saída
# de um na entrada do outro. A lógica de cada peça vive em
# terraform/modules/ (eks, rds e irsa), adaptados da Fase 4.
#
# Ordem natural das dependências (o Terraform a deduz das referências):
#   1. eks  — cluster, nós e provedor OIDC;
#   2. rds  — precisa do security group do cluster para liberar a 5432;
#   3. irsa — precisa do provedor OIDC do cluster para as trusts.
# O access entry do self-healing fica em self-healing.tf.
#
# CUSTO: é a raiz que cobra por hora (control plane, dois nós e o RDS).
# Ela é aplicada no início de cada janela de trabalho e destruída no fim,
# sempre com plano salvo (terraform plan -out) e depois que a raiz k8s
# tiver sido destruída.
# =================================================================

locals {
  # Nomes do desenho do projeto.
  node_group_name = "${var.project_name}-nodes"
  rds_identifier  = "${var.project_name}-postgres"

  # Usuário mestre do PostgreSQL. Só o Job de schema o usa, para criar os
  # bancos ngo_db e donation_db e um usuário próprio para cada serviço.
  rds_master_username = "solidary_admin"
}

# -----------------------------------------------------------------
# CLUSTER EKS
# -----------------------------------------------------------------

module "eks" {
  source = "../modules/eks"

  # Nome vindo da base (ver data.tf): é o mesmo da policy do self-healing.
  cluster_name       = local.eks_cluster_name
  name_prefix        = var.project_name
  kubernetes_version = var.kubernetes_version

  # Sub-redes privadas da base, nas duas AZs.
  subnet_ids                   = local.private_subnet_ids
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  node_group_name    = local.node_group_name
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_disk_size_gb  = var.node_disk_size_gb

  # As instâncias e os volumes dos nós não herdam o default_tags: as
  # tags obrigatórias vão explícitas no launch template.
  node_tags = local.required_tags
}

# -----------------------------------------------------------------
# BANCO POSTGRESQL (ngo-service e donation-service)
# -----------------------------------------------------------------

module "rds" {
  source = "../modules/rds"

  identifier = local.rds_identifier

  # Rede da base: a VPC do security group e o subnet group das sub-redes
  # de banco.
  vpc_id               = local.vpc_id
  db_subnet_group_name = local.database_subnet_group_name

  # Única origem aceita na porta 5432: o security group do cluster, que o
  # EKS coloca nos nós (o launch template não define outros grupos).
  allowed_security_group_id = module.eks.cluster_security_group_id

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage_gb  = var.db_allocated_storage_gb
  backup_retention_days = var.db_backup_retention_days
  master_username       = local.rds_master_username
}

# -----------------------------------------------------------------
# IDENTIDADES DOS PODS (IRSA)
# -----------------------------------------------------------------
# Uma role por ServiceAccount que fala com a AWS, com só as ações que o
# código do serviço chama, e só nos ARNs do projeto:
#   - donation-service publica o evento de doação na fila (SendMessage;
#     a URL da fila chega por variável de ambiente, sem GetQueueUrl);
#   - volunteer-service grava (PutItem) e lista (Scan) voluntários.
# O ngo-service não fala com a AWS e não recebe role.
# -----------------------------------------------------------------

module "irsa" {
  source = "../modules/irsa"

  name_prefix = var.project_name
  namespace   = var.app_namespace

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  service_accounts = {
    "donation-service" = {
      statements = [
        {
          sid       = "PublicarEventoDeDoacao"
          actions   = ["sqs:SendMessage"]
          resources = [local.sqs_queue_arn]
        },
      ]
    }

    "volunteer-service" = {
      statements = [
        {
          sid       = "GravarEListarVoluntarios"
          actions   = ["dynamodb:PutItem", "dynamodb:Scan"]
          resources = [local.dynamodb_table_arn]
        },
      ]
    }
  }
}
