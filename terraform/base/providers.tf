# =================================================================
# RAIZ BASE — provider AWS e tags obrigatórias
# =================================================================
# O provider traduz o código Terraform em chamadas à API da AWS. Os
# módulos chamados em main.tf herdam esta configuração: região, guarda
# de conta e tags.
# =================================================================

locals {
  # Tags de custo exigidas pelo enunciado, idênticas em todas as raízes.
  # São local, e não variável, de propósito: nenhum tfvars consegue
  # mudá-las ou apagá-las por engano. A chave de tag na AWS diferencia
  # maiúsculas de minúsculas: "project" não entraria no filtro "Project".
  required_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }
}

provider "aws" {
  region = var.aws_region

  # Guarda de conta: com credenciais de qualquer outra conta, o provider
  # se recusa a trabalhar antes de criar ou alterar qualquer coisa. Protege
  # contra um perfil errado da AWS CLI. Não protege o backend S3, que usa
  # as credenciais por conta própria.
  allowed_account_ids = [var.expected_aws_account_id]

  # Aplicadas a todo recurso desta raiz que aceita tags, inclusive os
  # criados dentro dos módulos (VPC, NAT, ECR, SQS, DynamoDB e IAM). É o
  # que permite somar o custo do projeto por tag no Cost Explorer e no
  # Budget.
  default_tags {
    tags = local.required_tags
  }
}
