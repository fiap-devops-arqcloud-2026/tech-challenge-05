# =================================================================
# NAMESPACE DA APLICAÇÃO
# =================================================================
# Criado aqui, e não pelo GitOps, por ordem de dependência: os Secrets, o
# ConfigMap e as ServiceAccounts desta raiz precisam de um namespace
# existente, e o ArgoCD só sincroniza depois.
#
# CONTRATO COM O GITOPS: os manifestos em gitops/ não devem declarar este
# Namespace nem os objetos criados por esta raiz. Se declararem, ArgoCD e
# Terraform passam a disputar os mesmos objetos (rótulos e anotações de
# rastreio), e cada sincronização desfaz o plano do outro.
# =================================================================

locals {
  # Rótulos comuns dos objetos que esta raiz cria dentro do namespace.
  # managed-by=terraform avisa a quem olha o cluster que a origem é o
  # Terraform, e não o ArgoCD: mudar à mão ou pelo GitOps não persiste.
  app_common_labels = {
    "app.kubernetes.io/part-of"    = var.project_name
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = local.app_namespace

    labels = {
      "app.kubernetes.io/part-of" = var.project_name
    }
  }

  lifecycle {
    # A fila e a tabela vivem na região da base, e o ConfigMap entrega
    # var.aws_region aos SDKs. Regiões diferentes fariam os serviços
    # procurarem a fila e a tabela no lugar errado (erro só em execução).
    precondition {
      condition     = local.base_aws_region == var.aws_region
      error_message = "aws_region desta raiz difere da região gravada no estado da raiz base. Use a mesma região em todas as raízes."
    }
  }
}
