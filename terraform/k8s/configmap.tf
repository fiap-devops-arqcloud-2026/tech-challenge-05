# =================================================================
# CONFIGMAP aws-endpoints — onde estão a fila e a tabela
# =================================================================
# Endereços da AWS que os serviços leem por variável de ambiente. Não são
# segredo, mas carregam o ID da conta (a URL da fila contém o número da
# conta). Criados aqui, a partir do estado da base, eles não precisam ir
# para os manifestos do repositório público.
#
# Nenhuma credencial AWS entra aqui nem em Secret: donation-service e
# volunteer-service recebem credenciais temporárias por IRSA
# (serviceaccounts.tf).
#
# Chaves = nomes exatos que o código dos serviços lê:
#   AWS_REGION          -> donation-service e volunteer-service (SDKs)
#   AWS_SQS_URL         -> donation-service (publica cada doação)
#   AWS_DYNAMODB_TABLE  -> volunteer-service (grava e lista voluntários)
# =================================================================

resource "kubernetes_config_map_v1" "aws" {
  metadata {
    name      = "aws-endpoints"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = "aws-endpoints" })
  }

  data = {
    # Mesma região da base (conferida pela precondition em namespace.tf).
    AWS_REGION         = var.aws_region
    AWS_SQS_URL        = local.sqs_queue_url
    AWS_DYNAMODB_TABLE = local.dynamodb_table_name
  }
}
