# =================================================================
# TESTE DO MÓDULO IRSA — trust amarrada e menor privilégio
# =================================================================
# A trust é a parte mais sensível do módulo: uma condição frouxa deixaria
# qualquer Pod do cluster assumir a role de outro serviço. Este arquivo
# prova, a cada alteração, que:
#
#   1. cada role só aceita o token da SUA ServiceAccount, no namespace
#      certo, emitido para o STS, pelo provedor OIDC do cluster;
#   2. cada role recebe só as ações e os ARNs declarados, e nada mais;
#   3. curingas e o emissor com "https://" são recusados na entrada,
#      antes de virarem policy.
#
# COMO RODA SEM AWS
# Todos os "run" usam command = plan: nada é criado. O provider usa
# credenciais falsas e aponta IAM e STS para 127.0.0.1:9, uma porta que
# recusa conexão: se algo tentasse falar com a AWS, o teste falharia na
# hora, em vez de tocar numa conta real. Os documentos de policy
# (aws_iam_policy_document) são montados localmente pelo provider, sem
# chamada de rede, e por isso o teste consegue ler o JSON final.
#
# POR QUE AS CHAVES SÃO FIXAS NAS ASSERÇÕES
# Cada asserção cita data.aws_iam_policy_document.<nome>["<chave>"].json
# com a chave escrita, e não num for. Com chave dinâmica, a mensagem de
# falha tenta exibir o objeto inteiro do data source, que tem atributos
# obsoletos (override_json, source_json), e o Terraform 1.16 trava ao
# formatá-la (panic "value has marks"), em vez de mostrar o erro.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/irsa init -backend=false
#   terraform -chdir=terraform/modules/irsa test
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
    iam = "http://127.0.0.1:9"
    sts = "http://127.0.0.1:9"
  }
}

# Valores fictícios no formato real (conta 000000000000).
variables {
  name_prefix       = "solidarytech"
  namespace         = "solidarytech"
  oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
  oidc_provider_url = "oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"

  # O mesmo mapa que a raiz cluster passa ao módulo.
  service_accounts = {
    "donation-service" = {
      statements = [
        {
          sid       = "PublicarEventoDeDoacao"
          actions   = ["sqs:SendMessage"]
          resources = ["arn:aws:sqs:us-east-2:000000000000:solidary-donations"]
        },
      ]
    }

    "volunteer-service" = {
      statements = [
        {
          sid       = "GravarEListarVoluntarios"
          actions   = ["dynamodb:PutItem", "dynamodb:Scan"]
          resources = ["arn:aws:dynamodb:us-east-2:000000000000:table/SolidaryTechVolunteers"]
        },
      ]
    }
  }
}

# -----------------------------------------------------------------
# 1. Trust: só a ServiceAccount certa, no namespace certo
# -----------------------------------------------------------------

run "trust_amarrada_a_cada_serviceaccount" {
  command = plan

  # donation-service
  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement[0].Condition.StringEquals["oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:sub"] == "system:serviceaccount:solidarytech:donation-service"
    error_message = "A role do donation-service deve aceitar só system:serviceaccount:solidarytech:donation-service."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement[0].Condition.StringEquals["oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:aud"] == "sts.amazonaws.com"
    error_message = "A trust do donation-service deve exigir tokens emitidos para o STS (aud)."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement[0].Principal.Federated == var.oidc_provider_arn && jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "A trust do donation-service deve permitir só sts:AssumeRoleWithWebIdentity, com o provedor OIDC do cluster como principal."
  }

  assert {
    # Um só statement e um só operador: um StringLike ou um segundo
    # statement ampliariam quem pode assumir a role.
    condition     = length(jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement) == 1 && keys(jsondecode(data.aws_iam_policy_document.assume["donation-service"].json).Statement[0].Condition) == ["StringEquals"]
    error_message = "A trust do donation-service não deve ganhar outro statement nem outro operador de condição."
  }

  # volunteer-service
  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement[0].Condition.StringEquals["oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:sub"] == "system:serviceaccount:solidarytech:volunteer-service"
    error_message = "A role do volunteer-service deve aceitar só system:serviceaccount:solidarytech:volunteer-service."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement[0].Condition.StringEquals["oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF:aud"] == "sts.amazonaws.com"
    error_message = "A trust do volunteer-service deve exigir tokens emitidos para o STS (aud)."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement[0].Principal.Federated == var.oidc_provider_arn && jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "A trust do volunteer-service deve permitir só sts:AssumeRoleWithWebIdentity, com o provedor OIDC do cluster como principal."
  }

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement) == 1 && keys(jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json).Statement[0].Condition) == ["StringEquals"]
    error_message = "A trust do volunteer-service não deve ganhar outro statement nem outro operador de condição."
  }

  # As roles usam a trust acima (comparada já decodificada: o provider
  # normaliza o JSON no plano) e seguem o padrão de nomes.
  assert {
    condition     = jsondecode(aws_iam_role.this["donation-service"].assume_role_policy) == jsondecode(data.aws_iam_policy_document.assume["donation-service"].json) && jsondecode(aws_iam_role.this["volunteer-service"].assume_role_policy) == jsondecode(data.aws_iam_policy_document.assume["volunteer-service"].json)
    error_message = "Cada role deve usar a trust gerada para a própria ServiceAccount."
  }

  assert {
    condition     = aws_iam_role.this["donation-service"].name == "solidarytech-donation-service-irsa" && aws_iam_role.this["volunteer-service"].name == "solidarytech-volunteer-service-irsa"
    error_message = "As roles devem se chamar <prefixo>-<ServiceAccount>-irsa."
  }

  assert {
    condition     = toset(keys(output.role_arns)) == toset(["donation-service", "volunteer-service"])
    error_message = "Deve existir uma role por ServiceAccount do mapa, e nenhuma além delas."
  }
}

# -----------------------------------------------------------------
# 2. Permissões: só as ações e os ARNs declarados
# -----------------------------------------------------------------

run "permissoes_minimas_por_servico" {
  command = plan

  assert {
    # Uma única ação ou um único recurso viram texto, e não lista, no
    # JSON do IAM.
    condition     = length(jsondecode(data.aws_iam_policy_document.permissions["donation-service"].json).Statement) == 1 && jsondecode(data.aws_iam_policy_document.permissions["donation-service"].json).Statement[0].Action == "sqs:SendMessage" && jsondecode(data.aws_iam_policy_document.permissions["donation-service"].json).Statement[0].Resource == "arn:aws:sqs:us-east-2:000000000000:solidary-donations"
    error_message = "O donation-service deve ter só sqs:SendMessage, e só na fila do projeto."
  }

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.permissions["volunteer-service"].json).Statement) == 1 && toset(jsondecode(data.aws_iam_policy_document.permissions["volunteer-service"].json).Statement[0].Action) == toset(["dynamodb:PutItem", "dynamodb:Scan"]) && jsondecode(data.aws_iam_policy_document.permissions["volunteer-service"].json).Statement[0].Resource == "arn:aws:dynamodb:us-east-2:000000000000:table/SolidaryTechVolunteers"
    error_message = "O volunteer-service deve ter só dynamodb:PutItem e dynamodb:Scan, e só na tabela do projeto."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.permissions["donation-service"].json).Statement[0].Effect == "Allow" && jsondecode(data.aws_iam_policy_document.permissions["volunteer-service"].json).Statement[0].Effect == "Allow"
    error_message = "As permissões devem ser concessões explícitas (Allow)."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this["donation-service"].policy) == jsondecode(data.aws_iam_policy_document.permissions["donation-service"].json) && jsondecode(aws_iam_role_policy.this["volunteer-service"].policy) == jsondecode(data.aws_iam_policy_document.permissions["volunteer-service"].json)
    error_message = "Cada role deve receber a policy gerada para a própria ServiceAccount."
  }
}

# -----------------------------------------------------------------
# 3. Entradas perigosas são recusadas
# -----------------------------------------------------------------

run "curinga_na_acao_e_recusado" {
  command = plan

  variables {
    service_accounts = {
      "donation-service" = {
        statements = [
          {
            sid       = "TudoNaFila"
            actions   = ["sqs:*"]
            resources = ["arn:aws:sqs:us-east-2:000000000000:solidary-donations"]
          },
        ]
      }
    }
  }

  expect_failures = [var.service_accounts]
}

run "curinga_no_recurso_e_recusado" {
  command = plan

  variables {
    service_accounts = {
      "volunteer-service" = {
        statements = [
          {
            sid       = "QualquerTabela"
            actions   = ["dynamodb:PutItem"]
            resources = ["*"]
          },
        ]
      }
    }
  }

  expect_failures = [var.service_accounts]
}

run "emissor_com_https_e_recusado" {
  command = plan

  variables {
    oidc_provider_url = "https://oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
  }

  expect_failures = [var.oidc_provider_url]
}
