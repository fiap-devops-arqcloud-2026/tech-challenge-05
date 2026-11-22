# =================================================================
# MÓDULO IAM-CI — identidades do GitHub Actions na AWS via OIDC
# =================================================================
# Em vez de guardar AWS_ACCESS_KEY_ID nos secrets do GitHub, o workflow
# apresenta um token assinado pelo próprio GitHub, e a AWS devolve
# credenciais temporárias que expiram sozinhas. Não há chave para vazar,
# rotacionar ou revogar.
#
# Duas roles, cada uma com só o que o seu trabalho exige:
#   - CI: publica imagens nos repositórios ECR do projeto;
#   - self-healing: localiza o cluster EKS para reiniciar Deployments.
# Um vazamento de uma não dá os poderes da outra.
#
# O provedor OIDC do GitHub NÃO é criado aqui: ele é um por conta e
# pertence à raiz bootstrap. Este módulo recebe o ARN dele.
# =================================================================

locals {
  # O repositório usa subject imutável: o GitHub escreve
  # repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>.
  # Com só os nomes (repo:owner/repo:...), a condição não casaria com o
  # token real e o CI receberia AccessDenied.
  github_repository_parts = split("/", var.github_repository)
  github_oidc_subject     = "repo:${local.github_repository_parts[0]}@${var.github_repository_owner_id}/${local.github_repository_parts[1]}@${var.github_repository_id}:ref:refs/heads/${var.github_deploy_branch}"
}

# -----------------------------------------------------------------
# Política de confiança: QUEM pode assumir as roles
# -----------------------------------------------------------------
# O data source não cria nada: monta o JSON da policy de forma validada,
# em vez de JSON solto que só revelaria um erro no apply.
# -----------------------------------------------------------------
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GithubOidcAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      # "Federated": identidade externa, emitida pelo provedor OIDC.
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    # O audience do token precisa ser o STS, o valor que a action
    # aws-actions/configure-aws-credentials pede. Isso impede que um token
    # emitido para outro destino seja reaproveitado aqui.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # A CONDIÇÃO MAIS IMPORTANTE DO MÓDULO. Sem ela, qualquer repositório
    # do GitHub no mundo poderia assumir as roles. StringEquals (e não
    # StringLike) exige o subject exato: só a branch configurada deste
    # repositório. Pull requests, outras branches, tags e jobs com
    # environment do GitHub têm outro subject e são recusados.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

# -----------------------------------------------------------------
# ROLE DO CI — publicação de imagens no ECR
# -----------------------------------------------------------------
resource "aws_iam_role" "ci" {
  name = "${var.project_name}-github-ci"
  # Descrições sem acentos: o texto vai para a API da AWS.
  description        = "Assumida pelo GitHub Actions via OIDC para publicar imagens no ECR do projeto."
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Menor privilégio: autenticar no registro e publicar imagens somente nos
# repositórios recebidos, sem nenhuma ação com curinga.
data "aws_iam_policy_document" "ci_ecr" {
  statement {
    sid     = "EcrAuthToken"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]

    # "*" aqui não é descuido: esta ação não tem permissão por recurso, e
    # com um ARN no lugar ela simplesmente não seria concedida. O token de
    # login sozinho não abre nenhum repositório: o escopo real do acesso
    # fica no statement seguinte.
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"

    actions = [
      # As cinco primeiras compõem o docker push, na ordem de uso:
      "ecr:BatchCheckLayerAvailability", # verifica quais camadas já existem
      "ecr:InitiateLayerUpload",         # abre o envio de uma camada nova
      "ecr:UploadLayerPart",             # envia os pedaços da camada
      "ecr:CompleteLayerUpload",         # fecha o envio da camada
      "ecr:PutImage",                    # registra o manifesto com a tag

      # As demais deixam o pipeline ler o que já existe: cache de build,
      # scan da imagem publicada e a checagem "esta tag já existe?", que
      # evita tentar sobrescrever uma tag imutável numa reexecução.
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]

    # Só os ARNs recebidos do módulo ECR. É isto que impede o CI de mexer
    # em qualquer outro repositório da conta.
    resources = var.ecr_repository_arns
  }
}

# Policy inline, e não gerenciada: só existe para esta role, nasce e morre
# com ela e dispensa o recurso de anexo. Também não tem o campo
# description, que numa policy gerenciada força recriar a policy (e o
# anexo) quando o texto muda.
resource "aws_iam_role_policy" "ci_ecr" {
  name = "${var.project_name}-github-ci-ecr"
  # .name (e não .id) porque o nome já é conhecido no plan; os testes
  # comparam este valor sem esperar o apply.
  role   = aws_iam_role.ci.name
  policy = data.aws_iam_policy_document.ci_ecr.json
}

# -----------------------------------------------------------------
# ROLE DO SELF-HEALING — reinício de Deployments no EKS
# -----------------------------------------------------------------
# Quando um alerta dispara, um workflow do GitHub Actions reinicia o
# Deployment com problema. Para falar com o EKS ele precisa de uma
# identidade AWS, separada da role de publicação de imagens.
#
# CONFIANÇA: a mesma trust acima. O repository_dispatch só roda workflows
# da branch padrão, então o token do self-healing tem o subject da main.
#
# PERMISSÃO AWS: só eks:DescribeCluster no cluster do projeto, o mínimo
# para montar o kubeconfig. O que a role pode fazer DENTRO do Kubernetes
# não vem do IAM: vem do access entry (raiz cluster) e do RBAC do grupo
# dela (GitOps), restrito a reiniciar os Deployments da aplicação.
# -----------------------------------------------------------------
resource "aws_iam_role" "self_healing" {
  name               = "${var.project_name}-github-self-healing"
  description        = "Assumida pelo workflow de self-healing via OIDC para reiniciar Deployments no EKS."
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "self_healing" {
  statement {
    sid     = "DescribeProjectCluster"
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]

    # ARN montado na raiz a partir do nome previsível do cluster: a base
    # nasce antes do cluster e não pode ler o estado dele.
    resources = [var.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "self_healing" {
  name   = "${var.project_name}-github-self-healing-eks"
  role   = aws_iam_role.self_healing.name
  policy = data.aws_iam_policy_document.self_healing.json
}
