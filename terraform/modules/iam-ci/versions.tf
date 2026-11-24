# =================================================================
# MÓDULO IAM-CI — versões
# =================================================================
# Um módulo não configura provider: ele herda o da raiz que o chama
# (região, guarda de conta e tags obrigatórias). Aqui fica declarado só
# de qual provider o módulo depende e em que faixa de versão. A faixa é a
# mesma das raízes, para que o init feito dentro do módulo (validação e
# terraform test) resolva a mesma linha de versão que a raiz usa.
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
