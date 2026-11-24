# =================================================================
# SAÍDAS — módulo eks
# =================================================================
# O que a raiz cluster repassa à raiz k8s (endpoint, CA, versão) e o que
# os módulos rds e irsa precisam (security group e provedor OIDC).
# =================================================================

output "cluster_name" {
  description = "Nome do cluster EKS (aws eks update-kubeconfig --name <este valor>)."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN do cluster EKS."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "URL da API do Kubernetes (campo server do kubeconfig)."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificado da autoridade certificadora do cluster, em base64. Sem ele, o cliente não confia no endpoint da API."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução no control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = <<-EOT
    Security group criado pelo EKS para o cluster. Ele fica no control
    plane e nos nós (o launch template não define outros grupos), então
    é a origem que o RDS autoriza na porta 5432.
  EOT
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do provedor OIDC do cluster: o principal Federated das trusts IRSA."
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "Emissor OIDC do cluster SEM o prefixo https://: o prefixo das condições <emissor>:sub e <emissor>:aud das trusts IRSA."
  value       = local.oidc_issuer
}

output "node_role_arn" {
  description = "ARN da role IAM das instâncias do node group."
  value       = aws_iam_role.node.arn
}

output "node_group_name" {
  description = "Nome do node group gerenciado."
  value       = aws_eks_node_group.this.node_group_name
}
