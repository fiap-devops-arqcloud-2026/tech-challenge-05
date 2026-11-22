# =================================================================
# VERSÕES — módulo eks
# =================================================================
# O módulo declara de qual provider precisa e a faixa de versões que
# aceita. A versão exata fica travada no .terraform.lock.hcl da raiz que
# o chama (terraform/cluster). A faixa é a mesma das raízes, para que
# módulo e raiz nunca discordem sobre a linha 6.x do provider AWS.
# =================================================================

terraform {
  # 1.11+ por causa do lock nativo do backend S3 (use_lockfile) usado
  # pelas raízes; o módulo segue o mesmo piso para não haver surpresa.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}
