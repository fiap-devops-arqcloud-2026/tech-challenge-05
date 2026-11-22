# =================================================================
# MÓDULO MESSAGING — fila SQS das doações e tabela DynamoDB
# =================================================================
# O donation-service publica um evento na fila a cada doação registrada,
# com o contexto de trace W3C nos atributos da mensagem. Nenhum serviço
# consome a fila hoje: ela desacopla o hot path de um consumidor futuro.
# O volunteer-service grava e consulta os voluntários na tabela DynamoDB.
# =================================================================

# -----------------------------------------------------------------
# Dead-letter queue (DLQ)
# -----------------------------------------------------------------
# Uma mensagem que sempre falha no consumidor voltaria para a fila sem
# fim, ocupando o consumidor. Depois de 5 leituras sem exclusão, a SQS a
# move para cá, onde ela fica guardada para investigação. É declarada
# antes da fila principal porque a principal referencia o ARN dela.
# -----------------------------------------------------------------
resource "aws_sqs_queue" "donations_dlq" {
  name = "${var.queue_name}-dlq"

  # 14 dias (60 * 60 * 24 * 14), o máximo da SQS: tempo de sobra para
  # investigar a mensagem antes que ela expire.
  message_retention_seconds = 1209600

  # Criptografia em repouso com chave gerenciada pela própria SQS, sem
  # custo. Com KMS, cada chamada à fila geraria também uma chamada cobrada
  # ao KMS.
  sqs_managed_sse_enabled = true
}

# -----------------------------------------------------------------
# Fila principal (Standard)
# -----------------------------------------------------------------
resource "aws_sqs_queue" "donations" {
  name = var.queue_name

  # 4 dias (60 * 60 * 24 * 4), o padrão da SQS. Enquanto não houver
  # consumidor, as mensagens expiram sozinhas e a fila não acumula para
  # sempre.
  message_retention_seconds = 345600

  # Tempo em que a mensagem lida fica invisível para outros consumidores.
  # Precisa ser maior que o processamento; senão, dois consumidores tratam
  # a mesma mensagem.
  visibility_timeout_seconds = 30

  # Long polling: a leitura espera até 20 s por uma mensagem em vez de
  # voltar vazia na hora. Menos chamadas à API, menos custo para o
  # consumidor que vier.
  receive_wait_time_seconds = 20

  sqs_managed_sse_enabled = true

  # A API espera JSON; jsonencode() converte a estrutura HCL. Referenciar o
  # ARN da DLQ também diz ao Terraform que ela precisa existir antes.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.donations_dlq.arn
    maxReceiveCount     = 5
  })
}

# -----------------------------------------------------------------
# Tabela dos voluntários
# -----------------------------------------------------------------
resource "aws_dynamodb_table" "volunteers" {
  name = var.dynamodb_table_name

  # Cobrança por requisição: sem capacidade reservada cobrando 24 horas
  # por dia num ambiente de tráfego baixo e intermitente.
  billing_mode = "PAY_PER_REQUEST"

  hash_key = var.dynamodb_partition_key

  # Só a chave precisa ser declarada. Os demais campos do item (name,
  # email, ngo_id, registered_at) são gravados livremente pelo serviço.
  attribute {
    name = var.dynamodb_partition_key
    type = "S"
  }

  # Toda tabela DynamoDB já é cifrada em repouso com uma chave da AWS.
  # enabled = true troca essa chave pela chave gerenciada aws/dynamodb no
  # KMS da conta, cujo uso fica auditável no CloudTrail. Ela não tem
  # mensalidade; as chamadas ao KMS são cobradas, e o DynamoDB as reduz
  # guardando a chave da tabela em cache por alguns minutos.
  server_side_encryption {
    enabled = true
  }

  # Recuperação para um ponto no tempo (PITR): backup contínuo que permite
  # restaurar a tabela em qualquer segundo da janela de retenção (35 dias
  # por padrão). É a proteção destes dados na estratégia de recuperação de
  # desastres. A restauração cria uma tabela nova, que depois é apontada
  # ao serviço. O custo acompanha o tamanho da tabela (GB-mês) e é
  # desprezível com poucos registros.
  point_in_time_recovery {
    enabled = true
  }

  # Ambiente efêmero: com a proteção ligada, o destroy falharia nesta
  # tabela.
  deletion_protection_enabled = false
}
