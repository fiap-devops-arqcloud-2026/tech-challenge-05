# =================================================================
# RAIZ BASE — saídas
# =================================================================
# Os nomes são um contrato: as raízes cluster e k8s os leem por
# terraform_remote_state, e o CI os usa como variáveis do repositório.
# Renomear uma saída quebra quem a consome.
#
# Nenhuma saída é segredo. URLs e ARNs carregam o ID da conta, que não é
# credencial, mas também não vai para arquivo versionado; por isso os
# consumidores leem estes valores do estado, e não de um arquivo no Git.
#   terraform -chdir=terraform/base output
# =================================================================

# -----------------------------------------------------------------
# Região e rede (consumidas pela raiz cluster)
# -----------------------------------------------------------------

output "aws_region" {
  description = "Região da infraestrutura, lida pelas raízes cluster e k8s e pelo CI."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID da VPC em que ficam o cluster e o banco."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Sub-redes privadas (uma por zona, na ordem de azs): nós do EKS e Pods."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Sub-redes públicas (uma por zona): NAT e eventuais load balancers públicos."
  value       = module.vpc.public_subnets
}

output "database_subnet_group_name" {
  description = "DB subnet group das sub-redes de banco, usado pelo RDS da raiz cluster."
  value       = module.vpc.database_subnet_group_name
}

# -----------------------------------------------------------------
# Registro de imagens (consumido pelo CI e pelo GitOps)
# -----------------------------------------------------------------

output "ecr_registry" {
  description = "Host do registro (<conta>.dkr.ecr.<região>.amazonaws.com), para o docker login do CI."
  value       = module.ecr.registry
}

output "ecr_repository_urls" {
  description = "Mapa serviço → URL do repositório ECR."
  value       = module.ecr.repository_urls
}

# -----------------------------------------------------------------
# Mensageria e tabela (consumidas pelas raízes cluster e k8s)
# -----------------------------------------------------------------

output "sqs_queue_name" {
  description = "Nome da fila das doações."
  value       = module.messaging.queue_name
}

output "sqs_queue_url" {
  description = "URL da fila: valor de AWS_SQS_URL no donation-service."
  value       = module.messaging.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila: recurso da policy IRSA do donation-service."
  value       = module.messaging.queue_arn
}

output "sqs_dlq_arn" {
  description = "ARN da dead-letter queue da fila das doações."
  value       = module.messaging.dlq_arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela: valor de AWS_DYNAMODB_TABLE no volunteer-service."
  value       = module.messaging.dynamodb_table_name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela: recurso da policy IRSA do volunteer-service."
  value       = module.messaging.dynamodb_table_arn
}

# -----------------------------------------------------------------
# Identidades do CI (consumidas pelo CI e pela raiz cluster)
# -----------------------------------------------------------------

output "ci_role_arn" {
  description = "Role que o CI assume via OIDC para publicar imagens (role-to-assume do workflow)."
  value       = module.iam_ci.ci_role_arn
}

output "self_healing_role_arn" {
  description = "Role do self-healing: a raiz cluster cria o access entry do EKS para ela, e o workflow de self-healing a assume."
  value       = module.iam_ci.self_healing_role_arn
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS que a raiz cluster deve criar; é o cluster liberado na policy do self-healing."
  value       = var.eks_cluster_name
}
