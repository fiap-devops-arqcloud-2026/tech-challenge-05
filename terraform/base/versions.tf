# =================================================================
# RAIZ BASE — versões e backend
# =================================================================
# Rede, registro de imagens, mensageria, tabela e identidades do CI: a
# parte barata e de vida longa da infraestrutura. O cluster (a parte
# cara) fica em outra raiz e pode ser destruído sem levar estas peças.
#
# Backend S3 parcial: a chave, a criptografia e o lock ficam fixos aqui;
# o bucket e a região vêm do backend.hcl local (ignorado pelo Git),
# preparado a partir de backend.hcl.example com o bucket criado pela
# raiz bootstrap. A validação offline usa init -backend=false, que não
# acessa o S3.
# =================================================================

terraform {
  # >= 1.11 porque o use_lockfile do backend S3 (lock por objeto no
  # próprio bucket, sem tabela DynamoDB) só existe a partir dessa versão.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ~> 6.73 aceita correções e novidades da linha 6, sem saltar para
      # uma versão maior com mudanças incompatíveis. A versão exata fica
      # travada no .terraform.lock.hcl, que é versionado.
      version = "~> 6.73"
    }
  }

  backend "s3" {
    key = "phase5/prod/base.tfstate"

    # O estado guarda ARNs, URLs e IDs em texto puro: fica cifrado no
    # bucket.
    encrypt = true

    # Lock nativo do S3: impede dois applies simultâneos no mesmo estado.
    use_lockfile = true
  }
}
