# =================================================================
# TESTE DO MÓDULO MESSAGING — fila, DLQ e tabela como o contrato pede
# =================================================================
# Prova, a cada alteração, que:
#   1. a fila e a DLQ têm os nomes esperados, criptografia e redrive para
#      a DLQ depois de 5 leituras, com a DLQ guardando 14 dias;
#   2. a tabela é PAY_PER_REQUEST, com chave volunteer_id (String),
#      criptografia e recuperação para um ponto no tempo (PITR);
#   3. nomes fora das regras da AWS são recusados pelas validações.
#
# COMO RODA SEM AWS
# Todos os "run" usam command = plan: nada é criado. O provider abaixo
# usa credenciais falsas e aponta SQS, DynamoDB e STS para 127.0.0.1:9,
# uma porta que recusa conexão: se algum recurso tentasse falar com a
# AWS, o teste falharia na hora. O ARN da DLQ (que só existe depois do
# apply) recebe um valor fixo por override_resource, para que a política
# de redrive seja conhecida já no plan.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/messaging init -backend=false -input=false
#   terraform -chdir=terraform/modules/messaging test
# =================================================================

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    dynamodb = "http://127.0.0.1:9"
    sqs      = "http://127.0.0.1:9"
    sts      = "http://127.0.0.1:9"
  }
}

variables {
  queue_name          = "solidary-donations"
  dynamodb_table_name = "SolidaryTechVolunteers"
}

override_resource {
  target          = aws_sqs_queue.donations_dlq
  override_during = plan
  values = {
    arn = "arn:aws:sqs:us-east-2:000000000000:solidary-donations-dlq"
  }
}

# -----------------------------------------------------------------
# 1. Fila e DLQ
# -----------------------------------------------------------------

run "queue_redrives_to_dlq" {
  command = plan

  assert {
    condition     = aws_sqs_queue.donations.name == "solidary-donations" && aws_sqs_queue.donations_dlq.name == "solidary-donations-dlq"
    error_message = "A fila e a DLQ devem se chamar solidary-donations e solidary-donations-dlq."
  }

  assert {
    condition     = aws_sqs_queue.donations.sqs_managed_sse_enabled && aws_sqs_queue.donations_dlq.sqs_managed_sse_enabled
    error_message = "A fila e a DLQ devem ter criptografia gerenciada pela SQS."
  }

  assert {
    condition     = aws_sqs_queue.donations_dlq.message_retention_seconds == 1209600
    error_message = "A DLQ deve guardar as mensagens por 14 dias."
  }

  assert {
    condition     = tonumber(jsondecode(aws_sqs_queue.donations.redrive_policy).maxReceiveCount) == 5
    error_message = "A mensagem deve ir para a DLQ depois de 5 leituras sem exclusão."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.donations.redrive_policy).deadLetterTargetArn == "arn:aws:sqs:us-east-2:000000000000:solidary-donations-dlq"
    error_message = "O redrive deve apontar para a DLQ deste módulo."
  }
}

# -----------------------------------------------------------------
# 2. Tabela DynamoDB
# -----------------------------------------------------------------

run "table_has_encryption_and_pitr" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.volunteers.name == "SolidaryTechVolunteers" && aws_dynamodb_table.volunteers.billing_mode == "PAY_PER_REQUEST"
    error_message = "A tabela deve se chamar SolidaryTechVolunteers e cobrar por requisição."
  }

  assert {
    condition     = aws_dynamodb_table.volunteers.hash_key == "volunteer_id" && one([for a in aws_dynamodb_table.volunteers.attribute : a.type if a.name == "volunteer_id"]) == "S"
    error_message = "A chave de partição deve ser volunteer_id, do tipo String."
  }

  assert {
    condition     = aws_dynamodb_table.volunteers.server_side_encryption[0].enabled
    error_message = "A tabela deve ter a criptografia com a chave gerenciada ligada."
  }

  assert {
    condition     = aws_dynamodb_table.volunteers.point_in_time_recovery[0].enabled
    error_message = "A tabela deve ter recuperação para um ponto no tempo (PITR) ligada."
  }

  assert {
    condition     = !aws_dynamodb_table.volunteers.deletion_protection_enabled
    error_message = "Ambiente efêmero: a proteção contra exclusão deve ficar desligada."
  }
}

# -----------------------------------------------------------------
# 3. Entradas inválidas
# -----------------------------------------------------------------
# expect_failures inverte a lógica: o run passa SOMENTE se a validação
# da variável indicada reprovar o valor.

# 77 caracteres: com o sufixo -dlq, o nome da DLQ passaria dos 80 da SQS.
run "reject_queue_name_too_long" {
  command = plan

  variables {
    queue_name = "fila-com-nome-longo-demais-para-sobrar-espaco-ao-sufixo-da-dlq-0123456789abcd"
  }

  expect_failures = [var.queue_name]
}

run "reject_invalid_table_name" {
  command = plan

  variables {
    dynamodb_table_name = "Tabela Com Espaços"
  }

  expect_failures = [var.dynamodb_table_name]
}
