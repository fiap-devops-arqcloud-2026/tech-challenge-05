# =================================================================
# VARIÁVEIS DE ENTRADA — módulo irsa
# =================================================================

variable "name_prefix" {
  description = "Prefixo dos nomes das roles (ex.: solidarytech gera solidarytech-donation-service-irsa)."
  type        = string
}

variable "namespace" {
  description = <<-EOT
    Namespace Kubernetes das ServiceAccounts. Entra na condição "sub" da
    trust, então precisa ser exatamente o namespace em que a raiz k8s
    cria as ServiceAccounts; senão o Pod sobe, mas recebe AccessDenied
    ao assumir a role.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "O namespace precisa ser um nome DNS válido do Kubernetes (minúsculas, dígitos e hífen, até 63 caracteres)."
  }
}

variable "oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster EKS (saída oidc_provider_arn do módulo eks)."
  type        = string
}

variable "oidc_provider_url" {
  description = "Emissor OIDC do cluster SEM o prefixo https:// (saída oidc_provider_url do módulo eks)."
  type        = string

  validation {
    # Erro clássico de IRSA: com o "https://", a chave de condição nunca
    # casa com a do token, e toda chamada termina em AccessDenied.
    condition     = length(var.oidc_provider_url) > 0 && !startswith(var.oidc_provider_url, "https://")
    error_message = "Informe o emissor OIDC sem o prefixo https://, como oidc.eks.us-east-2.amazonaws.com/id/<ID>."
  }
}

variable "service_accounts" {
  description = <<-EOT
    Mapa <nome da ServiceAccount> = { statements = [...] }: uma role por
    ServiceAccount, com as permissões listadas e nada além delas. Cada
    statement tem sid (só letras e dígitos, regra do IAM), actions e
    resources (ARNs). ServiceAccount que não fala com a AWS não entra no
    mapa e fica sem role.
  EOT
  type = map(object({
    statements = list(object({
      sid       = string
      actions   = list(string)
      resources = list(string)
    }))
  }))

  validation {
    condition     = alltrue([for name in keys(var.service_accounts) : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", name))])
    error_message = "Cada chave do mapa precisa ser o nome de uma ServiceAccount válida (minúsculas, dígitos e hífen)."
  }

  validation {
    # Limite do IAM para nome de role: 64 caracteres.
    condition     = alltrue([for name in keys(var.service_accounts) : length("${var.name_prefix}-${name}-irsa") <= 64])
    error_message = "O nome da role (<prefixo>-<ServiceAccount>-irsa) passaria de 64 caracteres, o limite do IAM."
  }

  validation {
    condition = alltrue(flatten([
      for sa in values(var.service_accounts) : concat(
        [length(sa.statements) > 0],
        [for st in sa.statements : can(regex("^[A-Za-z0-9]+$", st.sid)) && length(st.actions) > 0 && length(st.resources) > 0],
      )
    ]))
    error_message = "Cada ServiceAccount precisa de ao menos um statement, e cada statement de um sid alfanumérico, ações e recursos."
  }

  validation {
    # Menor privilégio verificado na entrada: nenhum curinga em ação
    # ("sqs:*") nem em recurso ("*" ou ARN terminado em "*"). Precisar
    # de um curinga é decisão a revisar, não um ajuste silencioso.
    condition = alltrue(flatten([
      for sa in values(var.service_accounts) : [
        for st in sa.statements : [
          for item in concat(st.actions, st.resources) : !strcontains(item, "*")
        ]
      ]
    ]))
    error_message = "Ações e recursos não podem usar curinga (*): liste cada ação e cada ARN."
  }
}
