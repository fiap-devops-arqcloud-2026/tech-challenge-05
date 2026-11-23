# =================================================================
# TESTES DA RAIZ BOOTSTRAP — sem AWS, sem custo
# =================================================================
# Provam, a cada alteração, as propriedades que não podem regredir:
#   1. bucket de estado com o nome do contrato, no namespace regional da
#      conta, protegido contra exclusão com objetos dentro, versionado,
#      cifrado, sem acesso público e só com TLS (o prevent_destroy não é
#      atributo do recurso e não aparece no plano de teste);
#   2. Budget filtrado pela tag Project, medindo o custo BRUTO (sem
#      créditos nem reembolsos) e com os quatro alertas;
#   3. tags de alocação de custo desligadas por padrão;
#   4. o import do provedor OIDC monta o ARN com a conta em uso;
#   5. entradas inválidas são recusadas antes de virar recurso.
#
# COMO RODA SEM AWS
# Todos os "run" usam command = plan: nada é criado. O provider abaixo
# usa credenciais falsas e aponta os serviços para 127.0.0.1:9, porta que
# recusa conexão: se algo tentasse falar com a AWS, o teste falharia na
# hora, em vez de tocar numa conta real. A identidade da conta, que
# exigiria o STS, vem fixa por override_data.
#
# COMO RODAR
#   terraform -chdir=terraform/bootstrap init -backend=false
#   terraform -chdir=terraform/bootstrap test
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
    budgets = "http://127.0.0.1:9"
    ce      = "http://127.0.0.1:9"
    iam     = "http://127.0.0.1:9"
    s3      = "http://127.0.0.1:9"
    sts     = "http://127.0.0.1:9"
  }
}

# Conta fictícia, a mesma dos arquivos .example.
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "000000000000"
    arn        = "arn:aws:iam::000000000000:user/offline-test"
    user_id    = "offline-test"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

# Sem import por padrão nos testes: importar exigiria ler o IAM.
variables {
  expected_aws_account_id              = "000000000000"
  budget_alert_emails                  = ["alertas@example.org"]
  import_existing_github_oidc_provider = false
}

# -----------------------------------------------------------------
# 1. Bucket de estado
# -----------------------------------------------------------------

run "bucket_de_estado_protegido" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "solidarytech-tfstate-000000000000-us-east-2-an"
    error_message = "O nome do bucket deve seguir <projeto>-tfstate-<conta>-<região>-an (namespace regional da conta)."
  }

  assert {
    condition     = aws_s3_bucket.state.bucket_namespace == "account-regional"
    error_message = "O bucket de estado deve nascer no namespace regional da conta (bucket_namespace = account-regional), onde nenhuma outra conta consegue criar o mesmo nome."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "O bucket de estado não pode ser apagado com objetos dentro (force_destroy = false)."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "O versionamento do bucket de estado deve estar ligado."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.state.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm]) == "AES256"
    error_message = "O bucket de estado deve cifrar em repouso com SSE-S3 (AES256)."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "Os quatro bloqueios de acesso público devem estar ligados."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "As ACLs devem ficar desligadas (BucketOwnerEnforced)."
  }

  assert {
    condition     = output.state_bucket_name == "solidarytech-tfstate-000000000000-us-east-2-an"
    error_message = "O output state_bucket_name deve devolver o nome do bucket."
  }
}

# try() transforma "atributo ausente" em falha de asserção, com a mensagem
# abaixo, em vez de erro de avaliação que interromperia os demais testes.
run "policy_nega_acesso_sem_tls" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.state.policy).Statement) == 1
    error_message = "A policy do bucket deve ter um único statement (a negação sem TLS)."
  }

  assert {
    condition     = try(jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect, null) == "Deny"
    error_message = "O statement da policy deve ser uma negação."
  }

  assert {
    condition     = try(jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"], null) == "false"
    error_message = "A negação deve valer para requisições sem TLS (condição Bool aws:SecureTransport = false)."
  }

  assert {
    condition = try(toset(jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Resource), null) == toset([
      "arn:aws:s3:::solidarytech-tfstate-000000000000-us-east-2-an",
      "arn:aws:s3:::solidarytech-tfstate-000000000000-us-east-2-an/*",
    ])
    error_message = "A negação deve cobrir o bucket e todos os objetos dele."
  }
}

run "lifecycle_limpa_versoes_antigas" {
  command = plan

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.state.rule[0].status == "Enabled"
    error_message = "A regra de lifecycle deve estar ativa."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.state.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Versões não correntes devem expirar em 90 dias."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.state.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Uploads incompletos devem ser abortados em 7 dias."
  }
}

# -----------------------------------------------------------------
# 2. Budget
# -----------------------------------------------------------------

run "budget_mede_custo_bruto_por_tag" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.name == "solidarytech-mensal" && output.budget_name == "solidarytech-mensal"
    error_message = "O Budget deve se chamar <projeto>-mensal."
  }

  assert {
    condition = (
      aws_budgets_budget.monthly.budget_type == "COST" &&
      aws_budgets_budget.monthly.time_unit == "MONTHLY" &&
      aws_budgets_budget.monthly.limit_amount == "50" &&
      aws_budgets_budget.monthly.limit_unit == "USD"
    )
    error_message = "O Budget deve ser de custo, mensal, de US$ 50 por padrão."
  }

  assert {
    condition     = aws_budgets_budget.monthly.cost_types[0].include_credit == false && aws_budgets_budget.monthly.cost_types[0].include_refund == false
    error_message = "Créditos e reembolsos devem ficar fora do custo, senão o alerta nunca dispara numa conta com créditos."
  }

  assert {
    condition     = one([for f in aws_budgets_budget.monthly.cost_filter : f.name == "TagKeyValue" && f.values == tolist(["user:Project$SolidaryTech"])])
    error_message = "O Budget deve filtrar pela tag Project=SolidaryTech (user:Project$SolidaryTech)."
  }

  assert {
    condition = nonsensitive(sort([
      for n in aws_budgets_budget.monthly.notification : "${n.notification_type}:${n.threshold}:${n.comparison_operator}:${n.threshold_type}"
      ])) == sort([
      "ACTUAL:50:GREATER_THAN:PERCENTAGE",
      "ACTUAL:80:GREATER_THAN:PERCENTAGE",
      "ACTUAL:100:GREATER_THAN:PERCENTAGE",
      "FORECASTED:100:GREATER_THAN:PERCENTAGE",
    ])
    error_message = "O Budget deve alertar no gasto real a 50%, 80% e 100% e na previsão a 100%."
  }
}

# -----------------------------------------------------------------
# 3. Tags de alocação de custo
# -----------------------------------------------------------------

run "tags_de_custo_desligadas_por_padrao" {
  command = plan

  assert {
    condition     = length(aws_ce_cost_allocation_tag.required) == 0
    error_message = "A ativação das tags de custo deve começar desligada (a AWS recusa tags que ainda não estão no faturamento)."
  }
}

run "tags_de_custo_ligadas" {
  command = plan

  variables {
    activate_cost_allocation_tags = true
  }

  assert {
    condition     = toset(keys(aws_ce_cost_allocation_tag.required)) == toset(["Project", "Environment", "CostCenter"])
    error_message = "Devem ser ativadas exatamente as tags Project, Environment e CostCenter."
  }

  assert {
    condition     = alltrue([for t in aws_ce_cost_allocation_tag.required : t.status == "Active"])
    error_message = "As tags de custo devem ficar com status Active."
  }
}

# -----------------------------------------------------------------
# 4. Provedor OIDC do GitHub
# -----------------------------------------------------------------

run "provedor_oidc_igual_ao_da_conta" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "O provedor deve apontar para o emissor de tokens do GitHub Actions."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "O único público aceito deve ser sts.amazonaws.com."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.thumbprint_list == tolist(["ab9d0263244dd0326eb67015705a667e79cfe998"])
    error_message = "O thumbprint padrão deve ser o que já está no provedor da conta, para o import não gerar diferença."
  }
}

# Com o import ligado (o padrão do projeto), o plan precisa LER o provedor
# existente no IAM. O override abaixo responde no lugar do IAM; sem ele,
# o plan tentaria 127.0.0.1:9 e falharia, o que prova que este caminho
# exercita de fato o bloco import, e não uma criação.
run "import_condicional_ligado" {
  command = plan

  variables {
    import_existing_github_oidc_provider = true
  }

  override_resource {
    target          = aws_iam_openid_connect_provider.github
    override_during = plan
    values = {
      arn = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  assert {
    condition     = output.github_oidc_provider_arn == "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
    error_message = "O output github_oidc_provider_arn deve devolver o ARN do provedor adotado."
  }
}

# -----------------------------------------------------------------
# Tags obrigatórias (mesmo mapa nas quatro raízes)
# -----------------------------------------------------------------
# O default_tags de cada raiz usa este mapa. Uma letra diferente numa
# chave ou num valor tiraria os recursos desta raiz do filtro por tag do
# Budget e do Cost Explorer, sem nenhum erro visível.
run "tags_obrigatorias_do_contrato" {
  command = plan

  assert {
    condition = local.required_tags == {
      Project     = "SolidaryTech"
      Environment = "Production"
      CostCenter  = "NGO-Core"
      ManagedBy   = "Terraform"
    }
    error_message = "As tags obrigatórias devem ser exatamente Project=SolidaryTech, Environment=Production, CostCenter=NGO-Core e ManagedBy=Terraform."
  }
}

# -----------------------------------------------------------------
# 5. Entradas inválidas
# -----------------------------------------------------------------

run "recusa_conta_invalida" {
  command = plan

  variables {
    expected_aws_account_id = "12345"
  }

  expect_failures = [var.expected_aws_account_id]
}

run "recusa_email_invalido" {
  command = plan

  variables {
    budget_alert_emails = ["isto-nao-e-um-email"]
  }

  expect_failures = [var.budget_alert_emails]
}

run "recusa_lista_de_emails_vazia" {
  command = plan

  variables {
    budget_alert_emails = []
  }

  expect_failures = [var.budget_alert_emails]
}

run "recusa_orcamento_nao_numerico" {
  command = plan

  variables {
    monthly_budget_usd = "cinquenta"
  }

  expect_failures = [var.monthly_budget_usd]
}

run "recusa_thumbprint_invalido" {
  command = plan

  variables {
    github_oidc_thumbprints = ["nao-e-sha1"]
  }

  expect_failures = [var.github_oidc_thumbprints]
}

run "recusa_prefixo_com_maiusculas" {
  command = plan

  variables {
    project_name = "SolidaryTech"
  }

  expect_failures = [var.project_name]
}
