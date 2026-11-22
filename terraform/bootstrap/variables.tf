# =================================================================
# VARIÁVEIS DE ENTRADA — raiz bootstrap
# =================================================================
# Valores reais (ID da conta e e-mail do Budget) ficam só no
# terraform.tfvars local, que o Git ignora. O terraform.tfvars.example
# mostra o formato com valores fictícios.
# =================================================================

# -----------------------------------------------------------------
# Variáveis comuns a todas as raízes
# -----------------------------------------------------------------

variable "project_name" {
  description = "Prefixo dos nomes dos recursos (bucket de estado e Budget). Igual em todas as raízes."
  type        = string
  default     = "solidarytech"
  nullable    = false

  validation {
    # Minúsculas, dígitos e hífen: o prefixo entra no nome do bucket, e o
    # S3 recusa maiúsculas e sublinhados.
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ter de 3 a 21 caracteres: começa com letra minúscula e segue com minúsculas, dígitos ou hífen."
  }
}

variable "aws_region" {
  description = "Região AWS principal do projeto. O bucket de estado nasce nela."
  type        = string
  default     = "us-east-2"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region deve ser um código de região da AWS, como us-east-2."
  }
}

variable "expected_aws_account_id" {
  description = "ID (12 dígitos) da conta AWS do projeto. O provider recusa credenciais de qualquer outra conta. Informe no terraform.tfvars local ou em TF_VAR_expected_aws_account_id, nunca em arquivo versionado."
  type        = string
  nullable    = false
  # Sem default de propósito: errar a conta é o pior erro possível aqui,
  # então quem aplica precisa declarar o valor conscientemente.

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "expected_aws_account_id deve ter exatamente 12 dígitos."
  }
}

# -----------------------------------------------------------------
# Provedor OIDC do GitHub
# -----------------------------------------------------------------

variable "github_oidc_thumbprints" {
  description = "Impressões digitais (SHA-1, 40 caracteres hexadecimais) gravadas no provedor OIDC do GitHub. O padrão é o valor que já está no provedor da conta, para o import não gerar diferença."
  type        = list(string)
  default     = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
  nullable    = false

  validation {
    # O IAM aceita de 1 a 5 impressões digitais por provedor.
    condition     = length(var.github_oidc_thumbprints) >= 1 && length(var.github_oidc_thumbprints) <= 5 && alltrue([for t in var.github_oidc_thumbprints : can(regex("^[0-9a-fA-F]{40}$", t))])
    error_message = "github_oidc_thumbprints deve ter de 1 a 5 valores, cada um com 40 caracteres hexadecimais."
  }
}

variable "import_existing_github_oidc_provider" {
  description = "true adota no estado o provedor OIDC do GitHub que já existe na conta (bloco import em github-oidc.tf); false cria um provedor novo, para uma conta que ainda não o tem. Voltar para false depois de um destroy do bootstrap, senão o plan falha com \"Cannot import non-existent remote object\"."
  type        = bool
  # A conta do projeto já tem o provedor desde a Fase 4: criar outro
  # falharia com EntityAlreadyExists, porque a AWS aceita um só por URL.
  default  = true
  nullable = false
}

# -----------------------------------------------------------------
# Budget
# -----------------------------------------------------------------

variable "monthly_budget_usd" {
  description = "Teto mensal do Budget, em dólares, como texto (formato do provider). Os alertas disparam em percentuais deste valor."
  type        = string
  default     = "50"
  nullable    = false

  validation {
    # try() devolve false em vez de erro quando o texto não é número.
    condition     = try(tonumber(var.monthly_budget_usd) > 0, false)
    error_message = "monthly_budget_usd deve ser um número positivo, como \"50\"."
  }
}

variable "budget_alert_emails" {
  description = "E-mails que recebem os alertas do Budget. Sem padrão: vem só do terraform.tfvars local (ignorado pelo Git)."
  type        = list(string)
  nullable    = false
  # E-mail é dado pessoal: sensitive esconde o valor no plan e no apply,
  # que podem aparecer em gravações e em logs do terminal.
  sensitive = true

  validation {
    # O AWS Budgets aceita até 10 assinantes de e-mail por notificação.
    condition     = length(var.budget_alert_emails) >= 1 && length(var.budget_alert_emails) <= 10 && alltrue([for e in var.budget_alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "budget_alert_emails deve ter de 1 a 10 endereços de e-mail válidos."
  }
}

# -----------------------------------------------------------------
# Tags de alocação de custo
# -----------------------------------------------------------------

variable "activate_cost_allocation_tags" {
  description = "true ativa Project, Environment e CostCenter como tags de alocação de custo no faturamento. Só funciona depois que as tags aparecem no faturamento (até 24 h após o primeiro recurso com elas); por isso começa em false."
  type        = bool
  default     = false
  nullable    = false
}
