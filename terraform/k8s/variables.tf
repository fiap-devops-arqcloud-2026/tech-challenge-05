# =================================================================
# VARIÁVEIS DE ENTRADA — raiz k8s
# =================================================================
# Nenhum segredo entra por variável: as senhas vêm do estado da raiz
# cluster (senha mestre do RDS) ou são geradas aqui (usuários de
# aplicação). O repositório GitOps é público, então o ArgoCD não precisa
# de token de leitura.
# =================================================================

# -----------------------------------------------------------------
# Variáveis comuns a todas as raízes
# -----------------------------------------------------------------

variable "project_name" {
  description = "Prefixo do projeto. Aqui nomeia a Application do ArgoCD e o rótulo app.kubernetes.io/part-of. Igual em todas as raízes."
  type        = string
  default     = "solidarytech"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ter de 3 a 21 caracteres: começa com letra minúscula e segue com minúsculas, dígitos ou hífen."
  }
}

variable "aws_region" {
  description = "Região AWS do projeto. Precisa ser a mesma da raiz base (conferido em namespace.tf)."
  type        = string
  default     = "us-east-2"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region deve ser um código de região da AWS, como us-east-2."
  }
}

variable "expected_aws_account_id" {
  description = "ID (12 dígitos) da conta AWS do projeto. O provider AWS recusa credenciais de qualquer outra conta. Informe no terraform.tfvars local ou em TF_VAR_expected_aws_account_id, nunca em arquivo versionado."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "expected_aws_account_id deve ter exatamente 12 dígitos."
  }
}

# -----------------------------------------------------------------
# Estados remotos (base e cluster)
# -----------------------------------------------------------------

variable "state_bucket" {
  description = "Bucket dos estados (output state_bucket_name do bootstrap). Mesmo valor do backend.hcl local."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket deve ser um nome de bucket S3 válido (3 a 63 caracteres: minúsculas, dígitos, ponto e hífen)."
  }

  validation {
    # Mesma regra da raiz cluster. O allowed_account_ids protege só o
    # provider AWS: não protege a leitura dos estados remotos nem o token
    # do "aws eks get-token". O bucket do projeto fica no namespace
    # regional da conta (<projeto>-tfstate-<conta>-<região>-an), e o S3 só
    # deixa a própria conta criar um bucket com esse sufixo: exigi-lo com a
    # conta esperada impede ler, por engano, os estados de outra conta.
    condition     = endswith(var.state_bucket, "-${var.expected_aws_account_id}-${var.state_region}-an")
    error_message = "state_bucket precisa estar no namespace regional da conta esperada: o nome termina em -<conta>-<região do bucket>-an, como em <projeto>-tfstate-<conta>-<região>-an."
  }
}

variable "state_region" {
  description = "Região do bucket dos estados (output state_bucket_region do bootstrap). Mesmo valor do backend.hcl local."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.state_region))
    error_message = "state_region deve ser um código de região da AWS, como us-east-2."
  }
}

# -----------------------------------------------------------------
# ArgoCD
# -----------------------------------------------------------------

variable "argocd_chart_version" {
  description = "Versão do chart argo-cd (repositório argoproj/argo-helm). 10.18.2 instala o Argo CD v3.6.2. Fixa de propósito: com versão em aberto, um apply na semana da gravação poderia trazer uma release nova e mudar o comportamento sem ninguém pedir."
  type        = string
  default     = "10.18.2"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_chart_version))
    error_message = "argocd_chart_version deve ser uma versão exata (X.Y.Z), sem faixas nem curingas."
  }
}

variable "argocd_apps_chart_version" {
  description = "Versão do chart argocd-apps, que cria a Application do projeto. Fixa pelo mesmo motivo do chart do ArgoCD."
  type        = string
  default     = "2.0.8"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_apps_chart_version))
    error_message = "argocd_apps_chart_version deve ser uma versão exata (X.Y.Z), sem faixas nem curingas."
  }
}

variable "gitops_repo_url" {
  description = "Repositório observado pelo ArgoCD: o próprio monorepo, com os manifestos em gitops/. É público, então dispensa credencial de leitura."
  type        = string
  default     = "https://github.com/fiap-devops-arqcloud-2026/tech-challenge-05.git"
  nullable    = false

  validation {
    # Só HTTPS: o ArgoCD clona sem chave SSH, e o projeto não guarda
    # credencial de repositório no cluster.
    condition     = can(regex("^https://[^\\s]+$", var.gitops_repo_url))
    error_message = "gitops_repo_url deve ser uma URL HTTPS, sem espaços."
  }
}

variable "gitops_revision" {
  description = "Branch (ou tag) observada pelo ArgoCD. É a main: é nela que o CI grava a nova tag de imagem."
  type        = string
  default     = "main"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", var.gitops_revision))
    error_message = "gitops_revision deve ser um nome de branch ou tag explícito, sem espaços nem curingas."
  }
}

variable "gitops_app_path" {
  description = "Pasta do overlay Kustomize observada dentro do repositório, relativa à raiz dele."
  type        = string
  default     = "gitops/overlays/prod"
  nullable    = false

  validation {
    # Caminho relativo e sem "..": o ArgoCD resolve a partir da raiz do
    # repositório e recusa sair dela.
    condition     = can(regex("^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", var.gitops_app_path)) && !strcontains(var.gitops_app_path, "..")
    error_message = "gitops_app_path deve ser um caminho relativo (sem / no início nem no fim e sem ..), como gitops/overlays/prod."
  }
}

variable "enable_applications" {
  description = "true cria a Application do projeto no ArgoCD (chart argocd-apps). Começa em false: só ligar quando a pasta do overlay existir na branch observada e as imagens estiverem publicadas no ECR, senão a Application nasce com erro de sincronização."
  type        = bool
  default     = false
  nullable    = false
}
