# =================================================================
# RAIZ BASE — composição
# =================================================================
# Este arquivo quase não cria recurso direto: ele chama os módulos e liga
# a saída de um na entrada do outro. A lógica de cada peça fica em
# ../modules. Custo fixo baixo; o item caro é o NAT Gateway, que
# enable_nat_gateway liga e desliga.
#
# Pré-requisito: a raiz bootstrap aplicada (bucket de estado e provedor
# OIDC do GitHub na conta).
# =================================================================

# Partição e conta das credenciais em uso. allowed_account_ids (em
# providers.tf) garante que a conta é a esperada; daqui sai o ARN do
# cluster, sem nenhum ID de conta escrito no código.
data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # Sub-redes /24 calculadas a partir do /16 da VPC, uma por zona e por
  # camada. Os deslocamentos separam as faixas e facilitam ler um IP:
  #   privadas  10.0.1.0/24,   10.0.2.0/24   (nós do EKS)
  #   públicas  10.0.101.0/24, 10.0.102.0/24 (NAT e load balancers)
  #   banco     10.0.201.0/24, 10.0.202.0/24 (RDS)
  # Com a VPC CNI, cada Pod recebe um IP da sub-rede privada; /24 dá folga
  # para os nós do projeto.
  private_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  public_subnets   = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 101)]
  database_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 201)]

  # ARN previsível do cluster: a base nasce antes dele e não pode ler o
  # estado da raiz cluster.
  eks_cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.eks_cluster_name}"
}

# -----------------------------------------------------------------
# REDE
# -----------------------------------------------------------------
# Módulo da comunidade: escrever à mão VPC, Internet Gateway, NAT, route
# tables e associações seria reproduzir o que ele já faz e testa.
# -----------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.8"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs  = var.azs

  # Privadas: sem rota de entrada da internet. Nós do EKS e Pods.
  private_subnets = local.private_subnets

  # Públicas: rota para o Internet Gateway. Só o NAT (e um eventual load
  # balancer público) mora aqui.
  public_subnets = local.public_subnets

  # Banco: sub-redes próprias para o RDS, agrupadas no DB subnet group que
  # a raiz cluster usa. Como as privadas, não recebem conexões vindas da
  # internet.
  database_subnets             = local.database_subnets
  create_database_subnet_group = true
  database_subnet_group_name   = "${var.project_name}-db"

  # Um único NAT em vez de um por zona: economiza um NAT inteiro ao custo
  # de um ponto único de falha na saída para a internet, aceitável num
  # ambiente efêmero. Desligado, nada nas sub-redes privadas alcança a
  # internet.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = true

  # DNS da VPC: sem ele, os nós não resolvem os endpoints da AWS nem o
  # endpoint privado da API do EKS.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags de descoberta do Kubernetes: dizem em que sub-redes um Service do
  # tipo LoadBalancer pode criar um balanceador público (elb) ou interno
  # (internal-elb). Gratuitas, evitam retrabalho se algo for exposto.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# -----------------------------------------------------------------
# Endpoints de gateway para S3 e DynamoDB
# -----------------------------------------------------------------
# Gratuitos (sem cobrança por hora nem por GB). O tráfego das sub-redes
# privadas para o S3 e o DynamoDB passa a ir direto pela rede da AWS, sem
# pagar o processamento por GB do NAT. Isso inclui as camadas das imagens
# do ECR, que ficam no S3, e as chamadas do volunteer-service ao DynamoDB.
#
# A policy padrão (acesso total ao serviço) é proposital: as camadas do
# ECR ficam em buckets S3 da própria AWS, e uma policy restrita aos
# buckets da conta quebraria o pull das imagens pelos nós.
# -----------------------------------------------------------------
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(["s3", "dynamodb"])

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Gateway"

  # Com single_nat_gateway, há uma route table privada, compartilhada
  # também pelas sub-redes de banco.
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.project_name}-${each.key}-gateway"
  }
}

# -----------------------------------------------------------------
# REGISTRO DE IMAGENS
# -----------------------------------------------------------------
module "ecr" {
  source = "../modules/ecr"

  project_name = var.project_name
  services     = var.services

  # O CI publica só tags com o SHA do commit; imutável, uma tag publicada
  # nunca troca de conteúdo.
  image_tag_mutability = "IMMUTABLE"

  # As 10 imagens mais recentes de cada repositório: margem de rollback
  # sem armazenamento crescendo para sempre.
  images_to_keep = 10
}

# -----------------------------------------------------------------
# MENSAGERIA E TABELA
# -----------------------------------------------------------------
module "messaging" {
  source = "../modules/messaging"

  queue_name          = var.sqs_queue_name
  dynamodb_table_name = var.dynamodb_table_name

  # Chave com que o volunteer-service grava cada item.
  dynamodb_partition_key = "volunteer_id"
}

# -----------------------------------------------------------------
# IDENTIDADES DO CI
# -----------------------------------------------------------------
# O provedor OIDC do GitHub é um por conta e pertence à raiz bootstrap;
# aqui ele só é lido. Se a bootstrap ainda não foi aplicada, o plan falha
# neste ponto, antes de criar qualquer coisa.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  lifecycle {
    # A trust das roles exige o audience sts.amazonaws.com. Um provedor
    # sem esse cliente faria todo AssumeRoleWithWebIdentity falhar com
    # "Incorrect token audience" no workflow; melhor falhar já no plan.
    postcondition {
      condition     = contains(self.client_id_list, "sts.amazonaws.com")
      error_message = "O provedor OIDC do GitHub precisa ter o cliente sts.amazonaws.com. Confira a raiz bootstrap."
    }
  }
}

module "iam_ci" {
  source = "../modules/iam-ci"

  project_name             = var.project_name
  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  # Identidade imutável do repositório e branch autorizada.
  github_repository          = var.github_repository
  github_repository_owner_id = var.github_repository_owner_id
  github_repository_id       = var.github_repository_id
  github_deploy_branch       = var.github_deploy_branch

  # A saída do módulo ECR vira a entrada do IAM: o push do CI fica
  # restrito aos repositórios criados aqui, em vez de ecr:* na conta. A
  # referência também faz o Terraform criar os repositórios antes da
  # policy.
  ecr_repository_arns = module.ecr.repository_arns

  # O self-healing só pode descrever este cluster.
  eks_cluster_arn = local.eks_cluster_arn
}

# -----------------------------------------------------------------
# Conferência de convenção (aviso, não erro)
# -----------------------------------------------------------------
# Um check não bloqueia o plan: só avisa. Se o nome do cluster fugir de
# <project_name>-eks, o aviso lembra de conferir se a raiz cluster usa o
# mesmo nome; senão, a policy do self-healing aponta para um cluster que
# não existe.
check "eks_cluster_name_convention" {
  assert {
    condition     = var.eks_cluster_name == "${var.project_name}-eks"
    error_message = "eks_cluster_name (${var.eks_cluster_name}) foge da convenção <project_name>-eks (${var.project_name}-eks). Confira se a raiz cluster cria o cluster com exatamente este nome."
  }
}
