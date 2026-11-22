# =================================================================
# SERVICEACCOUNTS DOS SERVIÇOS — identidade de cada Pod
# =================================================================
# IRSA (IAM Roles for Service Accounts): a anotação eks.amazonaws.com/
# role-arn faz o EKS injetar no Pod um token próprio, que o SDK da AWS
# troca por credenciais temporárias da role. Nenhuma chave de acesso em
# Secret, variável ou imagem.
#
# Cada role (raiz cluster) só confia na sua ServiceAccount, neste
# namespace, e só pode o mínimo:
#   donation-service  -> sqs:SendMessage na fila de doações
#   volunteer-service -> dynamodb:PutItem e dynamodb:Scan na tabela
#   ngo-service       -> nenhuma role: só fala com o PostgreSQL
#
# As ServiceAccounts nascem aqui, e não no GitOps, para o ARN da role
# (que contém o ID da conta) não precisar ir para o repositório público.
# Os Deployments só referenciam o nome em serviceAccountName.
# =================================================================

locals {
  # ServiceAccounts que falam com a AWS. Os nomes são as chaves do output
  # irsa_role_arns da raiz cluster (conferidas pela precondition abaixo).
  irsa_service_accounts = ["donation-service", "volunteer-service"]
}

resource "kubernetes_service_account_v1" "irsa" {
  for_each = toset(local.irsa_service_accounts)

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = each.key })

    annotations = {
      "eks.amazonaws.com/role-arn" = local.irsa_role_arns[each.key]
    }
  }

  lifecycle {
    # Falha no plan, com mensagem clara, se a raiz cluster não publicar a
    # role desta ServiceAccount. Sem a anotação, o Pod subiria sem
    # credencial e só falharia na primeira chamada à AWS.
    precondition {
      condition     = contains(keys(local.irsa_role_arns), each.key)
      error_message = "O output irsa_role_arns da raiz cluster precisa ter as chaves donation-service e volunteer-service."
    }
  }
}

resource "kubernetes_service_account_v1" "ngo" {
  metadata {
    name      = "ngo-service"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = "ngo-service" })
  }

  # O ngo-service não chama a API do Kubernetes nem a AWS. Sem o token
  # montado, um invasor que tome o contêiner não herda nem a identidade
  # do Pod no cluster.
  automount_service_account_token = false
}
