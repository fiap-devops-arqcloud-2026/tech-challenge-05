# =================================================================
# TESTE DO MÓDULO IAM-CI — quem pode assumir as roles via OIDC
# =================================================================
# A política de confiança (trust) é a parte mais sensível deste módulo:
# um curinga no lugar errado deixaria QUALQUER repositório do GitHub
# assumir as roles da conta. Este arquivo prova, a cada alteração, que:
#
#   1. a trust aceita exatamente o subject da branch main deste
#      repositório, com os IDs imutáveis do dono e do repositório, o
#      audience do STS e o provedor OIDC recebido;
#   2. curingas, "injeção de contexto" e um provedor OIDC que não seja o
#      do GitHub são recusados na entrada, antes de virarem policy;
#   3. a role do self-healing usa a mesma trust e só pode descrever o
#      cluster do projeto;
#   4. a role do CI só publica nos repositórios ECR recebidos.
#
# COMO RODA SEM AWS
# Todos os "run" usam command = plan: nada é criado. O módulo não lê nada
# da AWS (o ARN do provedor OIDC chega por variável), então não é preciso
# mock_provider; e um mock atrapalharia, porque trocaria o JSON real dos
# aws_iam_policy_document, que é justamente o que se quer conferir, por
# valores inventados. O provider abaixo usa credenciais falsas e aponta
# IAM e STS para 127.0.0.1:9, uma porta que recusa conexão: se algum
# recurso tentasse falar com a AWS, o teste falharia na hora, em vez de
# tocar numa conta real.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/iam-ci init -backend=false -input=false
#   terraform -chdir=terraform/modules/iam-ci test
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

# Valores do repositório real. Os IDs não são segredo: aparecem na API
# pública do GitHub e no próprio token OIDC. A conta 000000000000 é
# fictícia.
variables {
  project_name               = "solidarytech"
  github_oidc_provider_arn   = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
  github_repository          = "fiap-devops-arqcloud-2026/tech-challenge-05"
  github_repository_owner_id = "287716251"
  github_repository_id       = "1454212968"
  github_deploy_branch       = "main"
  ecr_repository_arns = [
    "arn:aws:ecr:us-east-2:000000000000:repository/solidarytech/ngo-service",
    "arn:aws:ecr:us-east-2:000000000000:repository/solidarytech/donation-service",
    "arn:aws:ecr:us-east-2:000000000000:repository/solidarytech/volunteer-service",
  ]
  eks_cluster_arn = "arn:aws:eks:us-east-2:000000000000:cluster/solidarytech-eks"
}

# -----------------------------------------------------------------
# 1. A trust aceita exatamente o subject da main
# -----------------------------------------------------------------

run "trust_accepts_only_main_of_this_repository" {
  command = plan

  # try(..., null): se alguém trocar o operador (StringLike, por exemplo),
  # a chave some de StringEquals e a asserção reprova com esta mensagem,
  # em vez de virar um erro de índice que interrompe os outros casos.
  assert {
    condition     = try(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], null) == "repo:fiap-devops-arqcloud-2026@287716251/tech-challenge-05@1454212968:ref:refs/heads/main"
    error_message = "A trust deve aceitar exatamente (StringEquals) o subject da main, com os dois IDs imutáveis."
  }

  assert {
    condition     = try(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"], null) == "sts.amazonaws.com"
    error_message = "O audience deve ser exatamente o STS, o valor usado pela action configure-aws-credentials."
  }

  # Um statement, um operador (StringEquals) e exatamente as duas chaves:
  # nada de StringLike ou de outro statement que amplie a autorização.
  assert {
    condition = (
      length(jsondecode(data.aws_iam_policy_document.trust.json).Statement) == 1 &&
      length(keys(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition)) == 1 &&
      contains(keys(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition), "StringEquals") &&
      try(length(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals), 0) == 2
    )
    error_message = "A trust não deve ganhar outro statement, outro operador nem outra condição."
  }

  # flatten([...]) aceita o valor como texto ou como lista: o documento
  # escreve um item único como texto e vários itens como lista.
  assert {
    condition = (
      jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Effect == "Allow" &&
      flatten([jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Action]) == ["sts:AssumeRoleWithWebIdentity"] &&
      flatten([jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Principal.Federated]) == [var.github_oidc_provider_arn]
    )
    error_message = "A trust deve liberar só sts:AssumeRoleWithWebIdentity ao provedor OIDC recebido."
  }

  assert {
    condition     = output.github_oidc_subject == "repo:fiap-devops-arqcloud-2026@287716251/tech-challenge-05@1454212968:ref:refs/heads/main"
    error_message = "O output github_oidc_subject deve mostrar o mesmo subject da trust."
  }
}

run "role_names_follow_contract" {
  command = plan

  assert {
    condition     = aws_iam_role.ci.name == "solidarytech-github-ci" && aws_iam_role.self_healing.name == "solidarytech-github-self-healing"
    error_message = "As roles devem se chamar <projeto>-github-ci e <projeto>-github-self-healing."
  }
}

run "different_repository_is_parameterized" {
  command = plan

  variables {
    github_repository          = "another-org/another-repo"
    github_repository_owner_id = "12345"
    github_repository_id       = "67890"
    github_deploy_branch       = "release/v1"
  }

  assert {
    condition     = try(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], null) == "repo:another-org@12345/another-repo@67890:ref:refs/heads/release/v1"
    error_message = "O módulo não pode fixar internamente os nomes ou os IDs deste repositório."
  }
}

# -----------------------------------------------------------------
# 2. Entradas perigosas são recusadas pelas validações
# -----------------------------------------------------------------
# expect_failures inverte a lógica: o run passa SOMENTE se a validação
# da variável indicada reprovar o valor.

run "reject_owner_wildcard" {
  command = plan

  variables {
    github_repository_owner_id = "*"
  }

  expect_failures = [var.github_repository_owner_id]
}

run "reject_repo_id_wildcard" {
  command = plan

  variables {
    github_repository_id = "*"
  }

  expect_failures = [var.github_repository_id]
}

run "reject_repo_name_wildcard" {
  command = plan

  variables {
    github_repository = "fiap-devops-arqcloud-2026/*"
  }

  expect_failures = [var.github_repository]
}

run "reject_branch_wildcard" {
  command = plan

  variables {
    github_deploy_branch = "*"
  }

  expect_failures = [var.github_deploy_branch]
}

# O sufixo ":environment:prod" tentaria encaixar outro contexto do token
# dentro do subject. Dois-pontos não são aceitos no nome da branch.
run "reject_context_injection" {
  command = plan

  variables {
    github_deploy_branch = "main:environment:prod"
  }

  expect_failures = [var.github_deploy_branch]
}

# O provedor OIDC do próprio EKS (o do IRSA) também é "Federated"; se a
# trust o aceitasse, Pods do cluster poderiam assumir as roles do CI.
run "reject_foreign_oidc_provider" {
  command = plan

  variables {
    github_oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
  }

  expect_failures = [var.github_oidc_provider_arn]
}

run "reject_ecr_wildcard" {
  command = plan

  variables {
    ecr_repository_arns = ["arn:aws:ecr:us-east-2:000000000000:repository/*"]
  }

  expect_failures = [var.ecr_repository_arns]
}

run "reject_empty_ecr_list" {
  command = plan

  variables {
    ecr_repository_arns = []
  }

  expect_failures = [var.ecr_repository_arns]
}

run "reject_cluster_wildcard" {
  command = plan

  variables {
    eks_cluster_arn = "arn:aws:eks:us-east-2:000000000000:cluster/*"
  }

  expect_failures = [var.eks_cluster_arn]
}

# -----------------------------------------------------------------
# 3. Self-healing: mesma trust, permissão mínima no cluster
# -----------------------------------------------------------------

run "self_healing_shares_trust_and_minimal_policy" {
  command = plan

  # jsondecode compara o conteúdo, e não o texto: o provider AWS normaliza
  # o JSON da role (espaços e ordem), e a comparação de texto reprovaria
  # duas policies idênticas.
  assert {
    condition     = jsondecode(aws_iam_role.self_healing.assume_role_policy) == jsondecode(data.aws_iam_policy_document.trust.json) && jsondecode(aws_iam_role.ci.assume_role_policy) == jsondecode(data.aws_iam_policy_document.trust.json)
    error_message = "As duas roles (CI e self-healing) devem usar a mesma trust da main."
  }

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.self_healing.json).Statement) == 1
    error_message = "A policy do self-healing deve ter um único statement."
  }

  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.self_healing.json).Statement[0].Action]) == ["eks:DescribeCluster"]
    error_message = "O self-healing só pode chamar eks:DescribeCluster na AWS; o que ele faz dentro do cluster vem do RBAC."
  }

  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.self_healing.json).Statement[0].Resource]) == [var.eks_cluster_arn]
    error_message = "O self-healing só pode descrever o cluster do projeto."
  }

  assert {
    condition     = aws_iam_role_policy.self_healing.role == aws_iam_role.self_healing.name && jsondecode(aws_iam_role_policy.self_healing.policy) == jsondecode(data.aws_iam_policy_document.self_healing.json)
    error_message = "A policy mínima deve estar presa à role do self-healing."
  }
}

# -----------------------------------------------------------------
# 4. CI: publica somente nos repositórios ECR recebidos
# -----------------------------------------------------------------

run "ci_policy_scoped_to_project_repositories" {
  command = plan

  assert {
    condition     = toset(flatten([for s in jsondecode(data.aws_iam_policy_document.ci_ecr.json).Statement : s.Resource if s.Sid == "EcrPushPull"])) == toset(var.ecr_repository_arns)
    error_message = "O push no ECR deve valer somente para os 3 repositórios recebidos."
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(data.aws_iam_policy_document.ci_ecr.json).Statement : s.Action if s.Sid == "EcrPushPull"]), "ecr:PutImage")
    error_message = "A role do CI precisa conseguir publicar (ecr:PutImage) nos repositórios recebidos."
  }

  assert {
    condition     = alltrue([for s in jsondecode(data.aws_iam_policy_document.ci_ecr.json).Statement : alltrue([for a in flatten([s.Action]) : !strcontains(a, "*")])])
    error_message = "Nenhuma ação pode usar curinga (como ecr:*)."
  }

  # GetAuthorizationToken é a única ação que a AWS exige com recurso "*".
  assert {
    condition     = alltrue([for s in jsondecode(data.aws_iam_policy_document.ci_ecr.json).Statement : s.Sid == "EcrAuthToken" ? flatten([s.Action]) == ["ecr:GetAuthorizationToken"] : !contains(flatten([s.Resource]), "*")])
    error_message = "Só o statement EcrAuthToken pode usar recurso \"*\", e ele só pode conter ecr:GetAuthorizationToken."
  }

  assert {
    condition     = aws_iam_role_policy.ci_ecr.role == aws_iam_role.ci.name && jsondecode(aws_iam_role_policy.ci_ecr.policy) == jsondecode(data.aws_iam_policy_document.ci_ecr.json)
    error_message = "A policy de push deve estar presa à role do CI."
  }
}
