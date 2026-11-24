# =================================================================
# VERSÕES — módulo irsa
# =================================================================
# Mesma faixa de versões das raízes; a versão exata fica no
# .terraform.lock.hcl de quem chama o módulo (e no deste diretório, que
# roda os testes).
# =================================================================

terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }
}
