# =================================================================
# SAÍDAS — raiz cluster
# =================================================================
# Os nomes são o contrato com a raiz k8s, que os lê por
# terraform_remote_state para configurar os providers kubernetes e helm
# e montar Secrets, ServiceAccounts e o ConfigMap. Renomear uma saída
# aqui quebra o plano de lá.
#
# Para ver tudo (a senha aparece como sensitive):
#   terraform -chdir=terraform/cluster output
# =================================================================

# -----------------------------------------------------------------
# CLUSTER
# -----------------------------------------------------------------

output "cluster_name" {
  description = "Nome do cluster EKS. Para o kubectl local: aws eks update-kubeconfig --region <região> --name <este valor>."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "URL da API do Kubernetes (host dos providers kubernetes e helm da raiz k8s)."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificado da autoridade certificadora do cluster, em base64. A raiz k8s o decodifica (base64decode) para confiar no endpoint."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução no control plane."
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group do cluster, presente nos nós: a única origem aceita pelo RDS na porta 5432."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "Provedor OIDC do cluster, base do IRSA. Não confundir com o provedor OIDC do GitHub (raiz bootstrap)."
  value       = module.eks.oidc_provider_arn
}

output "node_role_arn" {
  description = "ARN da role IAM dos nós do node group."
  value       = module.eks.node_role_arn
}

# -----------------------------------------------------------------
# BANCO
# -----------------------------------------------------------------

output "rds_address" {
  description = "Hostname do PostgreSQL (sem a porta), para DATABASE_URL e PGHOST."
  value       = module.rds.address
}

output "rds_port" {
  description = "Porta do PostgreSQL."
  value       = module.rds.port
}

output "rds_master_username" {
  description = "Usuário mestre do PostgreSQL, usado só pelo Job de schema."
  value       = module.rds.master_username
}

output "rds_master_password" {
  description = <<-EOT
    Senha do usuário mestre. SENSÍVEL: o Terraform mostra (sensitive
    value) no plano e no apply, e a raiz k8s a lê do estado para o Secret
    do Job de schema. Ela fica em texto puro no estado (por isso o bucket
    é cifrado e de acesso restrito); para ler de fato, só se necessário:
      terraform -chdir=terraform/cluster output -raw rds_master_password
  EOT
  value       = module.rds.master_password
  sensitive   = true
}

# -----------------------------------------------------------------
# IDENTIDADES DOS PODS
# -----------------------------------------------------------------

output "irsa_role_arns" {
  description = <<-EOT
    Mapa <ServiceAccount> = <ARN da role IRSA>, com donation-service e
    volunteer-service. A raiz k8s grava cada ARN na anotação
    eks.amazonaws.com/role-arn da ServiceAccount; assim nenhum ID da
    conta precisa ir para o Git.
  EOT
  value       = module.irsa.role_arns
}

output "app_namespace" {
  description = "Namespace da aplicação usado na condição sub das roles IRSA; a raiz k8s cria o namespace com este nome."
  value       = var.app_namespace
}
