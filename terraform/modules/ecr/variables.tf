# =================================================================
# MÓDULO ECR — entradas
# =================================================================
# Variáveis sem default são obrigatórias: quem chama o módulo precisa
# informá-las. As validações barram valores inválidos já no plan, com
# mensagem clara, em vez de deixar a API da AWS recusá-los no apply.
# =================================================================

variable "project_name" {
  description = "Prefixo (namespace) dos repositórios: cada um se chama <project_name>/<serviço>."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ter de 3 a 21 caracteres (minúsculas, números e hífen), começando por letra."
  }
}

variable "services" {
  description = "Serviços que ganham um repositório cada, com o nome completo usado no Kubernetes (ex.: ngo-service)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.services) > 0 && length(distinct(var.services)) == length(var.services)
    error_message = "Informe ao menos um serviço, sem repetição."
  }

  # Regra de nome do ECR: minúsculas e números, com separadores simples.
  # Uma maiúscula ou um sublinhado só seriam recusados no meio do apply.
  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", s))])
    error_message = "Cada serviço deve usar só letras minúsculas, números e hífens simples (ex.: ngo-service)."
  }
}

variable "image_tag_mutability" {
  description = "IMMUTABLE impede sobrescrever uma tag já publicada; MUTABLE permite."
  type        = string
  nullable    = false
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Use MUTABLE ou IMMUTABLE."
  }
}

variable "images_to_keep" {
  description = "Quantas imagens cada repositório guarda; as mais antigas expiram pela lifecycle policy."
  type        = number
  nullable    = false
  default     = 10

  validation {
    condition     = var.images_to_keep >= 1 && floor(var.images_to_keep) == var.images_to_keep
    error_message = "images_to_keep deve ser um número inteiro maior ou igual a 1."
  }
}
