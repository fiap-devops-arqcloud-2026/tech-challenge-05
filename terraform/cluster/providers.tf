# =================================================================
# PROVIDER AWS E TAGS OBRIGATÓRIAS — raiz cluster
# =================================================================
# Mesma configuração em todas as raízes do projeto:
#   - allowed_account_ids recusa credenciais de qualquer outra conta,
#     antes de qualquer criação (proteção contra perfil errado da CLI);
#   - default_tags aplica as tags obrigatórias a todo recurso que o
#     Terraform cria e que aceita tags.
#
# O default_tags NÃO alcança o que a AWS cria por conta própria: as
# instâncias e os volumes do node group (tratados no launch template do
# módulo eks) e os volumes dos PVCs (StorageClass da raiz k8s).
# =================================================================

locals {
  # Tags exigidas pelo enunciado, com a caixa exata das chaves (tag é
  # sensível a maiúsculas: "project" e "Project" são tags diferentes no
  # Cost Explorer), mais ManagedBy. Idênticas nas quatro raízes, para que
  # o filtro por tag do Budget some o custo de todas.
  required_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_aws_account_id]

  default_tags {
    tags = local.required_tags
  }
}
