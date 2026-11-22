# =================================================================
# PROVIDER AWS E TAGS OBRIGATÓRIAS — raiz bootstrap
# =================================================================
# Mesmo bloco em todas as raízes do projeto (base, cluster, k8s e esta),
# para que guarda de conta e tags sejam idênticas em toda a infraestrutura.
# =================================================================

locals {
  # Política de tags do FinOps: as três primeiras são exigidas pelo
  # enunciado, com a caixa exata (tag é sensível a maiúsculas: "project"
  # e "Project" são tags diferentes no Cost Explorer); ManagedBy mostra a
  # quem audita que o recurso nasceu do código, não do console.
  required_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }
}

provider "aws" {
  region = var.aws_region

  # Guarda de conta: se as credenciais da máquina forem de outra conta, o
  # provider recusa ANTES de criar qualquer coisa. Evita aplicar o projeto
  # na conta errada por causa de um perfil da AWS CLI trocado.
  allowed_account_ids = [var.expected_aws_account_id]

  # Toda tag declarada aqui entra automaticamente em todo recurso aws_*
  # desta raiz que aceita tags, sem repetir um bloco tags = {...} em cada um.
  default_tags {
    tags = local.required_tags
  }
}
