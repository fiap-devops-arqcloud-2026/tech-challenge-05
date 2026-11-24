# =================================================================
# TESTE DA RAIZ BASE — composição, sem AWS
# =================================================================
# O terraform validate confere a sintaxe e as referências, mas não roda
# as validações que dependem de valores nem o cálculo das sub-redes. Este
# arquivo prova, com plans e um apply simulados, que:
#   1. as sub-redes /24 saem do /16 da VPC como documentado;
#   2. o ARN do cluster na policy do self-healing usa a conta das
#      credenciais e o nome exato do cluster;
#   3. os endpoints de gateway de S3 e DynamoDB ficam na route table
#      privada, o NAT nasce ligado por padrão e, desligado, sai sem levar
#      os endpoints;
#   4. zonas de outra região e VPC que não seja /16 são recusadas;
#   5. as saídas que as raízes cluster e k8s leem existem com os nomes do
#      contrato.
#
# COMO RODA SEM AWS
# mock_provider troca o provider AWS por um simulado: nada é chamado na
# AWS, e cada atributo calculado recebe um valor inventado. Os três data
# sources que a raiz lê da conta recebem valores fixos (conta fictícia
# 000000000000), porque as validações do módulo iam-ci exigem ARNs bem
# formados. O JSON dos aws_iam_policy_document vira uma policy mínima
# válida, porque o provider confere o formato da policy mesmo simulado. A
# trust e as policies de verdade são testadas no módulo iam-ci, com o
# provider real.
#
# COMO RODAR
#   terraform -chdir=terraform/base init -backend=false -input=false
#   terraform -chdir=terraform/base test
# =================================================================

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn            = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
      client_id_list = ["sts.amazonaws.com"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# A única variável sem default; conta fictícia.
variables {
  expected_aws_account_id = "000000000000"
}

# -----------------------------------------------------------------
# 1 a 3. Composição com os padrões do projeto
# -----------------------------------------------------------------

run "defaults_compose_as_documented" {
  command = plan

  assert {
    condition     = module.vpc.private_subnets_cidr_blocks == tolist(["10.0.1.0/24", "10.0.2.0/24"])
    error_message = "As sub-redes privadas devem ser 10.0.1.0/24 e 10.0.2.0/24."
  }

  assert {
    condition     = module.vpc.public_subnets_cidr_blocks == tolist(["10.0.101.0/24", "10.0.102.0/24"])
    error_message = "As sub-redes públicas devem ser 10.0.101.0/24 e 10.0.102.0/24."
  }

  assert {
    condition     = module.vpc.database_subnets_cidr_blocks == tolist(["10.0.201.0/24", "10.0.202.0/24"])
    error_message = "As sub-redes de banco devem ser 10.0.201.0/24 e 10.0.202.0/24."
  }

  assert {
    condition     = local.eks_cluster_arn == "arn:aws:eks:us-east-2:000000000000:cluster/solidarytech-eks"
    error_message = "O ARN do cluster deve usar a partição, a região, a conta das credenciais e o nome exato do cluster."
  }

  assert {
    condition     = output.eks_cluster_name == "solidarytech-eks" && output.aws_region == "us-east-2"
    error_message = "Os outputs eks_cluster_name e aws_region devem refletir as variáveis."
  }

  assert {
    condition = alltrue([
      for key, ep in aws_vpc_endpoint.gateway :
      ep.vpc_endpoint_type == "Gateway" && ep.service_name == "com.amazonaws.us-east-2.${key}"
    ]) && length(aws_vpc_endpoint.gateway) == 2
    error_message = "Devem existir endpoints de gateway para s3 e dynamodb na região."
  }
}

# -----------------------------------------------------------------
# Tags obrigatórias (mesmo mapa nas quatro raízes)
# -----------------------------------------------------------------
# O default_tags do provider usa este mapa e o leva a todos os recursos
# desta raiz, inclusive os dos módulos. Uma letra diferente numa chave ou
# num valor tiraria a rede, o ECR, a fila e a tabela do filtro por tag do
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
# 4. Entradas recusadas
# -----------------------------------------------------------------
# expect_failures inverte a lógica: o run passa SOMENTE se a validação
# da variável indicada reprovar o valor.

# Trocar a região (para a de DR, por exemplo) sem trocar as zonas.
run "reject_zones_from_another_region" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [var.azs]
}

run "reject_single_zone" {
  command = plan

  variables {
    azs = ["us-east-2a"]
  }

  expect_failures = [var.azs]
}

run "reject_vpc_smaller_than_16" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/20"
  }

  expect_failures = [var.vpc_cidr]
}

run "reject_invalid_account_id" {
  command = plan

  variables {
    expected_aws_account_id = "conta-real"
  }

  expect_failures = [var.expected_aws_account_id]
}

# -----------------------------------------------------------------
# 3. Endpoints de gateway e NAT
# -----------------------------------------------------------------
# command = apply só simula a criação, para que os IDs das route tables
# existam e possam ser comparados. A URL dos repositórios recebe um valor
# fixo no formato real, porque a saída ecr_registry exige um único host.
run "endpoints_nas_route_tables_privadas_e_nat_ligado" {
  command = apply

  override_resource {
    target = module.ecr.aws_ecr_repository.this
    values = {
      arn            = "arn:aws:ecr:us-east-2:000000000000:repository/solidarytech/servico"
      repository_url = "000000000000.dkr.ecr.us-east-2.amazonaws.com/solidarytech/servico"
    }
  }

  assert {
    condition = (
      aws_vpc_endpoint.gateway["s3"].route_table_ids == toset(module.vpc.private_route_table_ids) &&
      aws_vpc_endpoint.gateway["dynamodb"].route_table_ids == toset(module.vpc.private_route_table_ids) &&
      length(module.vpc.private_route_table_ids) == 1
    )
    error_message = "Os endpoints de gateway de S3 e DynamoDB devem ficar na route table privada (uma só, com single_nat_gateway), a mesma das sub-redes dos nós e do banco."
  }

  # Pegadinha da Fase 4: o exemplo da base vinha com o NAT desligado, e
  # os nós não baixavam imagens. O padrão daqui precisa ligá-lo.
  assert {
    condition     = length(module.vpc.natgw_ids) == 1
    error_message = "Com os padrões, a base deve criar exatamente um NAT Gateway."
  }
}

# Base de pé entre janelas, sem cluster: o NAT sai, e os endpoints de
# gateway (gratuitos) e a route table privada continuam.
run "nat_desligado_mantem_os_endpoints" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(module.vpc.natgw_ids) == 0
    error_message = "Com enable_nat_gateway = false, nenhum NAT Gateway deve ser criado."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2 && length(module.vpc.private_route_table_ids) == 1
    error_message = "Sem NAT, os dois endpoints de gateway e a route table privada devem continuar existindo."
  }
}

# -----------------------------------------------------------------
# 5. Contrato com as raízes cluster e k8s (e com o CI)
# -----------------------------------------------------------------
# As raízes cluster e k8s leem estas saídas por terraform_remote_state, e
# os testes delas usam estados fictícios com os mesmos nomes. Este run é
# o lado da base desse contrato: uma saída renomeada ou removida aqui faz
# a asserção falhar na referência, ainda offline, em vez de quebrar só o
# plano real do cluster. command = apply só simula a criação, para que os
# valores calculados existam; a URL dos repositórios recebe um valor fixo
# no formato real, de onde sai o host do registro.
#
# Fica por último de propósito: uma referência a saída inexistente é erro
# de avaliação, e o Terraform pula os runs seguintes do arquivo.
run "saidas_do_contrato_com_cluster_e_k8s" {
  command = apply

  override_resource {
    target = module.ecr.aws_ecr_repository.this
    values = {
      arn            = "arn:aws:ecr:us-east-2:000000000000:repository/solidarytech/servico"
      repository_url = "000000000000.dkr.ecr.us-east-2.amazonaws.com/solidarytech/servico"
    }
  }

  assert {
    condition = alltrue([
      output.aws_region == "us-east-2",
      output.eks_cluster_name == "solidarytech-eks",
      output.vpc_id != null,
      output.vpc_cidr_block == "10.0.0.0/16",
      length(output.private_subnet_ids) == 2,
      length(output.public_subnet_ids) == 2,
      output.database_subnet_group_name == "solidarytech-db",
      output.sqs_queue_name == "solidary-donations",
      output.sqs_queue_url != null,
      output.sqs_queue_arn != null,
      output.sqs_dlq_arn != null,
      output.dynamodb_table_name == "SolidaryTechVolunteers",
      output.dynamodb_table_arn != null,
      output.ci_role_arn != null,
      output.self_healing_role_arn != null,
    ])
    error_message = "As saídas lidas pelas raízes cluster e k8s devem existir com os nomes do contrato."
  }

  assert {
    condition     = output.ecr_registry == "000000000000.dkr.ecr.us-east-2.amazonaws.com" && toset(keys(output.ecr_repository_urls)) == toset(["ngo-service", "donation-service", "volunteer-service"])
    error_message = "ecr_registry deve ser o host do registro, e ecr_repository_urls deve ter uma URL por serviço."
  }
}
