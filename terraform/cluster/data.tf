# =================================================================
# LEITURA DO ESTADO DA RAIZ BASE
# =================================================================
# A raiz base criou a rede, a fila, a tabela e as roles do CI; os
# identificadores vivem no estado dela. O terraform_remote_state LÊ esse
# estado e não altera nada do outro lado.
#
# Por que não copiar os valores para variáveis: se a base mudar uma
# sub-rede, esta raiz acompanha sozinha. Duas fontes da verdade divergem
# em silêncio.
#
# Os nomes dos outputs abaixo são o contrato com a raiz base; renomear
# um output lá quebra o plano daqui com "Unsupported attribute".
# =================================================================

locals {
  # Chave fixa do estado da base, a mesma do backend "s3" de
  # terraform/base/versions.tf.
  base_state_key = "phase5/prod/base.tfstate"
}

data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = local.base_state_key
    region = var.state_region
  }

  lifecycle {
    # Base e cluster precisam estar na mesma região: as sub-redes, a fila
    # e a tabela não existem em outra. Falhar aqui, com mensagem clara, é
    # melhor do que um erro de "subnet não encontrada" no meio do apply.
    postcondition {
      condition     = self.outputs.aws_region == var.aws_region
      error_message = "A raiz base foi aplicada em outra região. Use em aws_region a mesma região da base."
    }
  }
}

# -----------------------------------------------------------------
# Atalhos para os outputs da base usados nesta raiz
# -----------------------------------------------------------------

locals {
  base = data.terraform_remote_state.base.outputs

  # Rede: sub-redes privadas (EKS) e o subnet group das sub-redes de
  # banco (RDS). Nenhuma tem rota de ENTRADA a partir da internet (sem
  # Internet Gateway): as duas usam a route table privada da base, cuja
  # saída passa pelo NAT. O RDS não sai por ela, porque o security group
  # dele não tem regra de saída.
  vpc_id                     = local.base.vpc_id
  private_subnet_ids         = local.base.private_subnet_ids
  database_subnet_group_name = local.base.database_subnet_group_name

  # ARNs que limitam as policies IRSA aos recursos do projeto.
  sqs_queue_arn      = local.base.sqs_queue_arn
  dynamodb_table_arn = local.base.dynamodb_table_arn

  # Role do workflow de self-healing, mapeada a um grupo Kubernetes em
  # self-healing.tf.
  self_healing_role_arn = local.base.self_healing_role_arn

  # Nome do cluster decidido na base: a policy do self-healing de lá já
  # foi montada com o ARN deste nome. Usar o mesmo valor aqui elimina o
  # risco de o cluster nascer com outro nome e a policy apontar para o
  # vazio (quase aconteceu na Fase 4).
  eks_cluster_name = local.base.eks_cluster_name
}

# -----------------------------------------------------------------
# Conferência do NAT Gateway da base
# -----------------------------------------------------------------
# Os nós ficam em sub-redes privadas e baixam as imagens do ECR pela
# internet, via NAT. Com o NAT desligado na base (enable_nat_gateway =
# false), o node group fica minutos tentando e termina em
# NodeCreationFailure, e os Pods ficariam em ImagePullBackOff.
#
# É um check, e não uma precondition, de propósito: ele só AVISA no plano.
# Assim nunca bloqueia o destroy desta raiz, que deve continuar possível
# mesmo depois de o NAT ser desligado.
# -----------------------------------------------------------------

check "base_nat_gateway" {
  data "aws_nat_gateways" "base" {
    vpc_id = local.vpc_id

    filter {
      name   = "state"
      values = ["available"]
    }
  }

  assert {
    condition     = length(data.aws_nat_gateways.base.ids) > 0
    error_message = "A VPC da base não tem NAT Gateway disponível: os nós não conseguirão baixar imagens. Aplique a base com enable_nat_gateway = true antes desta raiz."
  }
}
