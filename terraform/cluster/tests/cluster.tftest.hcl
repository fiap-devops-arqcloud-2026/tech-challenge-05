# =================================================================
# TESTE DA RAIZ CLUSTER — contrato com as raízes base e k8s
# =================================================================
# Os módulos têm testes próprios (eks, rds e irsa). Este arquivo prova a
# composição da raiz, sem tocar na AWS e sem ler o estado real da base:
#
#   1. o cluster nasce com o nome decidido na base (o mesmo ARN da policy
#      do self-healing) e todas as saídas do contrato com a raiz k8s
#      existem;
#   2. só donation-service e volunteer-service recebem role IRSA;
#   3. o self-healing entra no cluster só como membro do grupo
#      Kubernetes próprio;
#   4. as proteções da raiz funcionam: base em outra região, bucket de
#      estado de outra conta, tamanhos de nós incoerentes e NAT ausente.
#
# COMO RODA SEM AWS
# mock_provider troca o provider AWS por um falso, e o estado da base é
# substituído por valores fictícios (override_data). Os runs com
# command = apply só simulam a criação. Os mocks com formato real (JSON
# de policy, versões e ARNs) existem porque o provider falso ainda
# aplica as validações do provider real.
#
# COMO RODAR
#   terraform -chdir=terraform/cluster init -backend=false
#   terraform -chdir=terraform/cluster test
# =================================================================

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}]}"
    }
  }

  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/mock-role"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-east-2:000000000000:cluster/solidarytech-eks"
      endpoint = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-east-2.eks.amazonaws.com"
      certificate_authority = [
        { data = "Q0VSVElGSUNBRE8tRklDVElDSU8=" },
      ]
      identity = [
        {
          oidc = [
            { issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" },
          ]
        },
      ]
    }
  }
}

# Estado fictício da raiz base, com os nomes de saída do contrato.
override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      aws_region                 = "us-east-2"
      vpc_id                     = "vpc-0123456789abcdef0"
      private_subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
      database_subnet_group_name = "solidarytech-db"
      sqs_queue_arn              = "arn:aws:sqs:us-east-2:000000000000:solidary-donations"
      dynamodb_table_arn         = "arn:aws:dynamodb:us-east-2:000000000000:table/SolidaryTechVolunteers"
      self_healing_role_arn      = "arn:aws:iam::000000000000:role/solidarytech-github-self-healing"
      eks_cluster_name           = "solidarytech-eks"
    }
  }
}

# A base tem NAT Gateway disponível (o caso normal).
override_data {
  target = data.aws_nat_gateways.base
  values = {
    ids = ["nat-0123456789abcdef0"]
  }
}

variables {
  expected_aws_account_id = "000000000000"
  state_bucket            = "solidarytech-tfstate-000000000000-us-east-2"
  state_region            = "us-east-2"
}

# -----------------------------------------------------------------
# 1 a 3. Composição e saídas
# -----------------------------------------------------------------

run "composicao_e_saidas" {
  command = apply

  assert {
    condition     = output.cluster_name == "solidarytech-eks"
    error_message = "O cluster deve nascer com o nome publicado pela base (eks_cluster_name), o mesmo da policy do self-healing."
  }

  assert {
    condition     = toset(keys(output.irsa_role_arns)) == toset(["donation-service", "volunteer-service"])
    error_message = "Só donation-service e volunteer-service devem ter role IRSA (o ngo-service não fala com a AWS)."
  }

  assert {
    condition     = output.app_namespace == "solidarytech" && output.rds_master_username == "solidary_admin" && output.rds_port == 5432
    error_message = "Namespace, usuário mestre e porta do banco devem seguir o desenho."
  }

  assert {
    # Cada saída do contrato com a raiz k8s precisa existir; uma saída
    # ausente ou renomeada faz esta asserção falhar na referência.
    condition = alltrue([
      output.cluster_endpoint != "",
      output.cluster_certificate_authority_data != "",
      output.cluster_version == "1.37",
      output.cluster_security_group_id != "",
      output.oidc_provider_arn != "",
      output.node_role_arn != "",
      output.rds_address != "",
      length(nonsensitive(output.rds_master_password)) == 24,
    ])
    error_message = "Todas as saídas do contrato com a raiz k8s devem existir com os nomes combinados."
  }

  assert {
    condition     = aws_eks_access_entry.self_healing.principal_arn == "arn:aws:iam::000000000000:role/solidarytech-github-self-healing" && aws_eks_access_entry.self_healing.kubernetes_groups == toset(["solidarytech-self-healing"]) && aws_eks_access_entry.self_healing.type == "STANDARD"
    error_message = "A role do self-healing deve entrar no cluster só como membro do grupo solidarytech-self-healing."
  }

  assert {
    condition     = aws_eks_access_entry.self_healing.cluster_name == output.cluster_name
    error_message = "O access entry do self-healing deve ser criado no cluster desta raiz."
  }
}

# -----------------------------------------------------------------
# Tags obrigatórias (mesmo mapa nas quatro raízes)
# -----------------------------------------------------------------
# Este mapa vai para o default_tags do provider e, como node_tags, para
# as instâncias e os volumes dos nós. Uma letra diferente numa chave ou
# num valor tiraria o maior custo da conta do filtro por tag do Budget.
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
# 4. Proteções da raiz
# -----------------------------------------------------------------

run "base_em_outra_regiao_e_recusada" {
  command = plan

  override_data {
    target = data.terraform_remote_state.base
    values = {
      outputs = {
        aws_region                 = "us-east-1"
        vpc_id                     = "vpc-0123456789abcdef0"
        private_subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
        database_subnet_group_name = "solidarytech-db"
        sqs_queue_arn              = "arn:aws:sqs:us-east-1:000000000000:solidary-donations"
        dynamodb_table_arn         = "arn:aws:dynamodb:us-east-1:000000000000:table/SolidaryTechVolunteers"
        self_healing_role_arn      = "arn:aws:iam::000000000000:role/solidarytech-github-self-healing"
        eks_cluster_name           = "solidarytech-eks"
      }
    }
  }

  expect_failures = [data.terraform_remote_state.base]
}

# O nome do bucket precisa conter o ID da conta esperada. Um bucket sem
# ele (como o de outra conta) é recusado antes de qualquer leitura de
# estado. O nome usa texto no lugar de outro ID de 12 dígitos, para que a
# varredura de IDs de conta só encontre a conta fictícia 000000000000.
run "bucket_de_estado_de_outra_conta_e_recusado" {
  command = plan

  variables {
    state_bucket = "solidarytech-tfstate-outra-conta-us-east-2"
  }

  expect_failures = [var.state_bucket]
}

run "tamanhos_de_nos_incoerentes_sao_recusados" {
  command = plan

  variables {
    node_desired_size = 4
  }

  expect_failures = [var.node_desired_size]
}

run "base_sem_nat_gera_aviso" {
  command = plan

  override_data {
    target = data.aws_nat_gateways.base
    values = {
      ids = []
    }
  }

  expect_failures = [check.base_nat_gateway]
}
