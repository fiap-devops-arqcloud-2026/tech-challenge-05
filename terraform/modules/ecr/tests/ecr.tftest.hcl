# =================================================================
# TESTE DO MÓDULO ECR — o que o contrato da base exige dos repositórios
# =================================================================
# Prova, a cada alteração, que os repositórios:
#   1. seguem o nome <projeto>/<serviço>;
#   2. têm tag imutável, scan no push, AES256 e force_delete;
#   3. expiram as imagens além das 10 mais recentes;
#   4. devolvem o host do registro extraído da URL da AWS;
# e que entradas inválidas são recusadas pelas validações.
#
# COMO RODA SEM AWS
# Todos os "run" usam command = plan: nada é criado. O provider abaixo
# usa credenciais falsas e aponta ECR e STS para 127.0.0.1:9, uma porta
# que recusa conexão: se algum recurso tentasse falar com a AWS, o teste
# falharia na hora, em vez de tocar numa conta real. A URL do repositório
# (que só existe depois do apply) recebe um valor fixo por
# override_resource.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/ecr init -backend=false -input=false
#   terraform -chdir=terraform/modules/ecr test
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
    ecr = "http://127.0.0.1:9"
    sts = "http://127.0.0.1:9"
  }
}

variables {
  project_name = "solidarytech"
  services     = ["ngo-service", "donation-service", "volunteer-service"]
}

# URL fictícia, com a conta 000000000000, para o output registry ser
# conhecido já no plan.
override_resource {
  target          = aws_ecr_repository.this
  override_during = plan
  values = {
    repository_url = "000000000000.dkr.ecr.us-east-2.amazonaws.com/solidarytech/servico"
  }
}

# -----------------------------------------------------------------
# 1 e 2. Nomes e configuração dos repositórios
# -----------------------------------------------------------------

run "repositories_follow_contract" {
  command = plan

  assert {
    condition     = toset([for r in aws_ecr_repository.this : r.name]) == toset(["solidarytech/ngo-service", "solidarytech/donation-service", "solidarytech/volunteer-service"])
    error_message = "Os repositórios devem se chamar <projeto>/<serviço>, um por serviço."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Por padrão, toda tag publicada deve ser imutável."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_scanning_configuration[0].scan_on_push && r.encryption_configuration[0].encryption_type == "AES256" && r.force_delete])
    error_message = "Todo repositório deve ter scan no push, AES256 e force_delete."
  }
}

# -----------------------------------------------------------------
# 3. Lifecycle: só as 10 imagens mais recentes
# -----------------------------------------------------------------

run "lifecycle_keeps_ten_most_recent" {
  command = plan

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 3
    error_message = "Cada repositório deve ter a sua lifecycle policy."
  }

  assert {
    condition = alltrue([
      for p in aws_ecr_lifecycle_policy.this :
      jsondecode(p.policy).rules[0].selection.countType == "imageCountMoreThan" &&
      jsondecode(p.policy).rules[0].selection.countNumber == 10 &&
      jsondecode(p.policy).rules[0].action.type == "expire"
    ])
    error_message = "A lifecycle policy deve expirar o que passar das 10 imagens mais recentes."
  }
}

# -----------------------------------------------------------------
# 4. Host do registro
# -----------------------------------------------------------------

run "registry_comes_from_repository_url" {
  command = plan

  assert {
    condition     = output.registry == "000000000000.dkr.ecr.us-east-2.amazonaws.com"
    error_message = "O output registry deve ser o host da URL, sem o caminho do repositório."
  }
}

# -----------------------------------------------------------------
# Entradas inválidas
# -----------------------------------------------------------------
# expect_failures inverte a lógica: o run passa SOMENTE se a validação
# da variável indicada reprovar o valor.

run "reject_invalid_service_name" {
  command = plan

  variables {
    services = ["NGO_Service"]
  }

  expect_failures = [var.services]
}

run "reject_duplicated_service" {
  command = plan

  variables {
    services = ["ngo-service", "ngo-service"]
  }

  expect_failures = [var.services]
}

run "reject_unknown_mutability" {
  command = plan

  variables {
    image_tag_mutability = "SOMETIMES"
  }

  expect_failures = [var.image_tag_mutability]
}
