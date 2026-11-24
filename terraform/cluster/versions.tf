# =================================================================
# VERSÕES E BACKEND — raiz cluster
# =================================================================
# A raiz cara do projeto: EKS, RDS e as identidades dos Pods. Ela é
# criada no início de cada janela de trabalho e destruída no fim.
#
# Backend S3 parcial: a chave (key) fica fixa aqui, e o bucket e a região
# vêm do backend.hcl local, ignorado pelo Git e criado a partir do
# backend.hcl.example:
#
#   terraform init -backend-config=backend.hcl
#
# A validação offline (init -backend=false) não acessa o S3.
# =================================================================

terraform {
  # use_lockfile (trava do estado por objeto no próprio S3, sem tabela
  # DynamoDB) exige o Terraform 1.11 ou mais novo.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }

    # Senha do usuário mestre do RDS (módulo rds).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  backend "s3" {
    key = "phase5/prod/cluster.tfstate"
    # Cifra o objeto do estado no S3. O estado desta raiz guarda a senha
    # mestra do RDS em texto puro: o sensitive só a esconde do terminal.
    encrypt = true
    # Dois applies simultâneos esbarram na trava em vez de corromper o
    # estado.
    use_lockfile = true
  }
}
