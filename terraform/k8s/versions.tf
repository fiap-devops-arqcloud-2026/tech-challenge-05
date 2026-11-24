# =================================================================
# VERSÕES E BACKEND — raiz k8s
# =================================================================
# Objetos do Kubernetes que dependem de valores da AWS (endereço do RDS,
# URL da fila, ARNs das roles IRSA) e a instalação do ArgoCD.
#
# POR QUE UMA RAIZ SEPARADA DO CLUSTER
# Os providers kubernetes e helm precisam do endereço e do certificado do
# cluster para serem configurados. Na mesma raiz que cria o EKS, esses
# valores ainda não existem no plan ("provider configuration cannot be
# evaluated"). Separados, o cluster já está de pé e no estado quando esta
# raiz roda, e tudo é conhecido no plan.
#
# Ordem: bootstrap -> base -> cluster -> k8s. O destroy segue a ordem
# inversa: esta raiz SEMPRE sai antes do cluster.
# =================================================================

terraform {
  # 1.11+ pelo use_lockfile do backend S3; teto para não aceitar a 2.x
  # sem revisão.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    # Só para a guarda de conta (ver data.tf): nenhum recurso AWS nasce
    # aqui, mas o provider confere se as credenciais são da conta certa.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }

    # Namespace, StorageClass, Secrets, ConfigMap e ServiceAccounts. Linha
    # 3.x: os recursos com sufixo _v1 usados aqui são os atuais.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }

    # Instalação do ArgoCD e da Application. Na linha 3.x, kubernetes = {}
    # e exec = {} do provider são ATRIBUTOS (com "="), não blocos.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }

    # Senhas dos usuários de aplicação dos bancos.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Backend parcial: bucket e região vêm do backend.hcl local (ignorado
  # pelo Git). O estado desta raiz guarda as senhas dos bancos em texto
  # puro; por isso o bucket é privado, cifrado e só aceita TLS.
  backend "s3" {
    key          = "phase5/prod/k8s.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
