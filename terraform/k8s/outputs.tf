# =================================================================
# SAÍDAS — raiz k8s
# =================================================================
# Só nomes de objetos do Kubernetes: nenhuma senha sai daqui. Para ler a
# senha inicial do ArgoCD, veja o README (ela fica num Secret do cluster,
# não no estado do Terraform).
# =================================================================

output "app_namespace" {
  description = "Namespace da aplicação, onde ficam os Secrets, o ConfigMap e as ServiceAccounts desta raiz e os Deployments do GitOps."
  value       = kubernetes_namespace_v1.app.metadata[0].name
}

output "argocd_namespace" {
  description = "Namespace do ArgoCD (e da Application do projeto)."
  value       = helm_release.argocd.namespace
}

output "db_secret_names" {
  description = "Secrets de banco criados por esta raiz, por consumidor: ngo-service e donation-service (DATABASE_URL) e schema-job (variáveis PG* e senhas dos usuários de aplicação, para o Job de schema)."
  value = {
    "ngo-service"      = kubernetes_secret_v1.ngo_db.metadata[0].name
    "donation-service" = kubernetes_secret_v1.donation_db.metadata[0].name
    "schema-job"       = kubernetes_secret_v1.db_schema.metadata[0].name
  }
}

output "aws_config_map_name" {
  description = "ConfigMap com AWS_REGION, AWS_SQS_URL e AWS_DYNAMODB_TABLE, lido por envFrom/configMapKeyRef nos Deployments."
  value       = kubernetes_config_map_v1.aws.metadata[0].name
}
