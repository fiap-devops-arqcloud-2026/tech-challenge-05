# =================================================================
# MÓDULO IRSA — uma role IAM por ServiceAccount, sem chave estática
# =================================================================
# IRSA (IAM Roles for Service Accounts), em uma frase: em vez de guardar
# AWS_ACCESS_KEY_ID num Secret, o Pod recebe um token assinado pelo
# cluster e o troca por credencial temporária da AWS.
#
#   1. a ServiceAccount do Pod leva a anotação eks.amazonaws.com/role-arn
#      (criada pela raiz k8s com a saída irsa_role_arns da raiz cluster);
#   2. o EKS injeta no Pod o token OIDC e as variáveis que o SDK procura;
#   3. o SDK chama sts:AssumeRoleWithWebIdentity com esse token;
#   4. a AWS confere a assinatura no provedor OIDC do cluster e as
#      condições da trust (sub e aud), e devolve credenciais que expiram
#      e se renovam sozinhas.
#
# Mudança em relação à Fase 4: lá as policies eram fixas no módulo, presas
# às chaves de dois serviços. Aqui o módulo é genérico e as permissões de
# cada ServiceAccount são declaradas por quem chama (terraform/cluster/
# main.tf), onde ficam visíveis lado a lado. As validações do mapa
# recusam curingas, e o teste (tests/irsa.tftest.hcl) prova a trust e o
# menor privilégio sem tocar na AWS.
# =================================================================

# -----------------------------------------------------------------
# TRUST — quem pode assumir cada role
# -----------------------------------------------------------------
# Cada role só pode ser assumida pela SUA ServiceAccount, no SEU
# namespace. Sem essa amarração, qualquer Pod do cluster assumiria
# qualquer role, e o menor privilégio seria só aparência.
# -----------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  for_each = var.service_accounts

  statement {
    sid = "ServiceAccountWebIdentity"
    # Sufixo WithWebIdentity: troca de um token OIDC, e não o
    # sts:AssumeRole comum.
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      # A identidade vem de um provedor externo: o OIDC do próprio
      # cluster EKS.
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      # "sub" identifica quem pede, no formato do EKS:
      # system:serviceaccount:<namespace>:<ServiceAccount>.
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${each.key}"]
    }

    condition {
      # "aud" confirma que o token foi emitido para o STS; um token feito
      # para outro destino não serve aqui.
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.service_accounts

  name               = "${var.name_prefix}-${each.key}-irsa"
  description        = "IRSA da ServiceAccount ${var.namespace}/${each.key}: credenciais temporarias, sem chave estatica."
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

# -----------------------------------------------------------------
# PERMISSÕES — o que cada role pode fazer
# -----------------------------------------------------------------
# Policy em linha (aws_iam_role_policy), e não gerenciada: as permissões
# são exclusivas de uma role e nascem e morrem com ela, sem policy solta
# na conta depois do destroy.
# -----------------------------------------------------------------

data "aws_iam_policy_document" "permissions" {
  for_each = var.service_accounts

  dynamic "statement" {
    for_each = each.value.statements

    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.service_accounts

  name   = "${var.name_prefix}-${each.key}"
  role   = aws_iam_role.this[each.key].name
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
