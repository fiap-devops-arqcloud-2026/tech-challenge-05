# =================================================================
# LEITURA DOS ESTADOS DAS RAÍZES BASE E CLUSTER
# =================================================================
# terraform_remote_state é SOMENTE LEITURA: lê os outputs gravados no
# estado das outras raízes, sem alterar nada do outro lado.
#
# Os nomes dos outputs abaixo são o contrato entre as raízes. Renomear um
# output em base ou cluster quebra esta raiz no plan, com "Unsupported
# attribute" apontando para a linha exata deste arquivo.
#
# Se o cluster não tiver sido aplicado (ou já tiver sido destruído), o
# plan falha aqui com "Unable to find remote state" ou com outputs
# ausentes: é o comportamento desejado, melhor do que tentar criar
# objetos num cluster que não existe.
# =================================================================

locals {
  # Chaves fixas da Fase 5, as mesmas declaradas no backend de cada raiz.
  base_state_key    = "phase5/prod/base.tfstate"
  cluster_state_key = "phase5/prod/cluster.tfstate"
}

data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = local.base_state_key
    region = var.state_region
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = local.cluster_state_key
    region = var.state_region
  }
}

# -----------------------------------------------------------------
# GUARDA DE CONTA
# -----------------------------------------------------------------
# Nenhum recurso aws_* nasce nesta raiz, e o Terraform só configura um
# provider que alguém usa. Sem esta consulta, o allowed_account_ids do
# provider AWS nunca seria avaliado e a guarda de conta não valeria aqui.
# Com ela, o plan falha logo de início se as credenciais forem de outra
# conta, e como todo apply usa um plano salvo, um plano gerado na conta
# errada nunca chega a existir.
# -----------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------
# Atalhos para os outputs usados nesta raiz
# -----------------------------------------------------------------
locals {
  # --- raiz base ---

  # Região em que a base criou fila e tabela (conferida em namespace.tf).
  base_aws_region = data.terraform_remote_state.base.outputs.aws_region

  # Endereços consumidos pelos serviços no ConfigMap aws-endpoints.
  sqs_queue_url       = data.terraform_remote_state.base.outputs.sqs_queue_url
  dynamodb_table_name = data.terraform_remote_state.base.outputs.dynamodb_table_name

  # --- raiz cluster ---

  # Acesso à API do Kubernetes (providers.tf).
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_data  = data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data

  # Banco: endereço, porta e credencial mestre.
  rds_address         = data.terraform_remote_state.cluster.outputs.rds_address
  rds_port            = data.terraform_remote_state.cluster.outputs.rds_port
  rds_master_username = data.terraform_remote_state.cluster.outputs.rds_master_username

  # PEGADINHA: o output é sensitive na raiz cluster, mas o
  # terraform_remote_state NÃO preserva essa marca (conferido com o
  # Terraform 1.16). Sem o sensitive() abaixo, a senha apareceria em texto
  # no plan se alguém a usasse num output ou num atributo comum.
  #
  # LIMITE: o sensitive() vale só para este local. O próprio data source
  # continua guardando a senha SEM a marca no estado desta raiz, e a mostra
  # em texto em "terraform show", "terraform state show
  # data.terraform_remote_state.cluster", "terraform console" e em
  # mensagens de erro que citem data.terraform_remote_state.cluster.outputs.
  # Não rode esses comandos nesta raiz com a tela gravada; para conferir
  # saídas, use "terraform output".
  rds_master_password = sensitive(data.terraform_remote_state.cluster.outputs.rds_master_password)

  # Mapa <ServiceAccount> => <ARN da role IRSA> (donation-service e
  # volunteer-service; o ngo-service não fala com a AWS).
  irsa_role_arns = data.terraform_remote_state.cluster.outputs.irsa_role_arns

  # Namespace da aplicação. Vem do cluster, e não de uma variável daqui,
  # porque a trust de cada role IRSA está amarrada a
  # system:serviceaccount:<namespace>:<sa>. Uma fonte só evita que os dois
  # lados divirjam e o Pod receba AccessDenied ao assumir a role.
  app_namespace = data.terraform_remote_state.cluster.outputs.app_namespace
}
