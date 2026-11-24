# =================================================================
# MÓDULO IAM-CI — entradas
# =================================================================
# Estas entradas decidem QUEM pode assumir as roles e ONDE elas agem. Por
# isso nenhuma tem default que abra acesso, e as validações recusam
# curingas e "injeção de contexto" antes que virem policy. Os testes em
# tests/trust.tftest.hcl provam cada uma dessas recusas.
# =================================================================

variable "project_name" {
  description = "Prefixo dos nomes das roles: <project_name>-github-ci e <project_name>-github-self-healing."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ter de 3 a 21 caracteres (minúsculas, números e hífen), começando por letra."
  }
}

# O provedor OIDC do GitHub é UM por conta e pertence à raiz bootstrap.
# Este módulo só recebe o ARN dele: não cria, não altera e não apaga.
variable "github_oidc_provider_arn" {
  description = "ARN do provedor OIDC do GitHub Actions na conta (arn:aws:iam::<conta>:oidc-provider/token.actions.githubusercontent.com)."
  type        = string
  nullable    = false

  # Só o emissor do GitHub Actions é aceito. Apontar a trust para outro
  # provedor (o OIDC do EKS, por exemplo) deixaria outra identidade
  # assumir as roles do CI.
  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn deve ser o ARN do provedor token.actions.githubusercontent.com da conta."
  }
}

variable "github_repository" {
  description = "Repositório autorizado a assumir as roles, no formato owner/repo."
  type        = string
  nullable    = false
  # Sem default de propósito: um valor errado aqui abriria as roles para
  # outro repositório. Quem chama precisa declarar.

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository deve ser owner/repo, sem curingas nem contexto OIDC."
  }
}

# Os dois IDs abaixo entram no subject do token porque o repositório usa
# subject imutável: o GitHub escreve owner@ID/repo@ID. Se o repositório
# for apagado e recriado com o mesmo nome, o ID muda e a trust antiga
# deixa de valer. São tipados como texto (só dígitos) para preservar o
# valor exato e permitir que a validação recuse curingas.
variable "github_repository_owner_id" {
  description = "ID numérico imutável do dono (organização ou usuário) do repositório GitHub."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id deve ser um ID numérico positivo do GitHub."
  }
}

variable "github_repository_id" {
  description = "ID numérico imutável do repositório GitHub."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_id))
    error_message = "github_repository_id deve ser um ID numérico positivo do GitHub."
  }
}

variable "github_deploy_branch" {
  description = "Branch exata autorizada a assumir as roles; deve acompanhar o gate do pipeline."
  type        = string
  nullable    = false
  default     = "main"

  # Sem curinga, dois-pontos ou espaço: o dois-pontos permitiria encaixar
  # outro contexto do token (como :environment:prod) dentro do subject.
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", var.github_deploy_branch))
    error_message = "github_deploy_branch deve ser um nome de branch explícito, sem curingas, dois-pontos ou espaços."
  }
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR em que o CI pode publicar imagens."
  type        = list(string)
  nullable    = false
  # Recebido de module.ecr.repository_arns na raiz: a permissão acompanha
  # automaticamente os repositórios que existem de fato.

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "Informe ao menos um repositório ECR."
  }

  # ARN completo de repositório, sem curinga: "repository/*" daria ao CI
  # push em qualquer repositório da conta.
  validation {
    condition     = alltrue([for arn in var.ecr_repository_arns : can(regex("^arn:aws(-[a-z]+)*:ecr:[a-z0-9-]+:[0-9]{12}:repository/[a-z0-9]+([._/-][a-z0-9]+)*$", arn))])
    error_message = "Cada item de ecr_repository_arns deve ser o ARN completo de um repositório ECR, sem curingas."
  }
}

variable "eks_cluster_arn" {
  description = "ARN do cluster EKS do projeto: único recurso em que a role do self-healing pode chamar eks:DescribeCluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:eks:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9][A-Za-z0-9_-]*$", var.eks_cluster_arn))
    error_message = "eks_cluster_arn deve ser o ARN completo de um cluster EKS, sem curingas."
  }
}
