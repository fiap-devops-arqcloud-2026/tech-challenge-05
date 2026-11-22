# =================================================================
# MÓDULO MESSAGING — entradas
# =================================================================
# Os nomes chegam prontos da raiz, sem prefixo calculado aqui: a fila e a
# tabela têm nomes fixados pela documentação do projeto, e o código dos
# serviços os recebe por variável de ambiente.
# =================================================================

variable "queue_name" {
  description = "Nome da fila Standard que recebe os eventos de doação. A DLQ recebe o mesmo nome com o sufixo -dlq."
  type        = string
  nullable    = false

  # A SQS aceita até 80 caracteres (letras, números, hífen e sublinhado);
  # 4 ficam reservados para o sufixo -dlq.
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,76}$", var.queue_name))
    error_message = "queue_name deve ter de 1 a 76 caracteres (letras, números, hífen e sublinhado); o sufixo -dlq completa o limite de 80 da SQS."
  }
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB dos voluntários, lido pelo volunteer-service em AWS_DYNAMODB_TABLE."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,255}$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name deve ter de 3 a 255 caracteres (letras, números, ponto, hífen e sublinhado)."
  }
}

variable "dynamodb_partition_key" {
  description = "Chave de partição (tipo String) da tabela. O volunteer-service grava cada item com volunteer_id."
  type        = string
  nullable    = false
  default     = "volunteer_id"

  validation {
    condition     = length(var.dynamodb_partition_key) >= 1 && length(var.dynamodb_partition_key) <= 255
    error_message = "dynamodb_partition_key deve ter de 1 a 255 caracteres."
  }
}
