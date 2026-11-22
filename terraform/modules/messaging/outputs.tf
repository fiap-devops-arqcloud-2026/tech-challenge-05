# =================================================================
# MÓDULO MESSAGING — saídas
# =================================================================
# Estes valores só existem depois do apply (a URL e os ARNs levam o
# número da conta). A raiz base os repassa às raízes cluster (policies
# IRSA) e k8s (ConfigMap com os endereços que os serviços leem).
# =================================================================

output "queue_name" {
  description = "Nome da fila principal."
  value       = aws_sqs_queue.donations.name
}

output "queue_url" {
  description = "URL da fila: valor de AWS_SQS_URL no donation-service."
  value       = aws_sqs_queue.donations.url
}

output "queue_arn" {
  description = "ARN da fila: recurso da policy IRSA do donation-service (sqs:SendMessage)."
  value       = aws_sqs_queue.donations.arn
}

output "dlq_name" {
  description = "Nome da dead-letter queue."
  value       = aws_sqs_queue.donations_dlq.name
}

output "dlq_url" {
  description = "URL da dead-letter queue, para inspecionar mensagens que falharam."
  value       = aws_sqs_queue.donations_dlq.url
}

output "dlq_arn" {
  description = "ARN da dead-letter queue."
  value       = aws_sqs_queue.donations_dlq.arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela: valor de AWS_DYNAMODB_TABLE no volunteer-service."
  # Devolve o nome confirmado pelo recurso, não a variável de entrada.
  value = aws_dynamodb_table.volunteers.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela: recurso da policy IRSA do volunteer-service (dynamodb:PutItem e dynamodb:Scan)."
  value       = aws_dynamodb_table.volunteers.arn
}
