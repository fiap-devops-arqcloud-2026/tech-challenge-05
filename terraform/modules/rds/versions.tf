# =================================================================
# VERSÕES — módulo rds
# =================================================================
# Mesma faixa de versões das raízes. O provider random gera a senha do
# usuário mestre; sem declará-lo aqui, o init da raiz não o baixaria
# para o módulo.
# =================================================================

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
