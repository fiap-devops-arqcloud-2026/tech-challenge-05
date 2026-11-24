# =================================================================
# SAÍDAS — raiz bootstrap
# =================================================================
# Nenhuma é segredo. O nome do bucket contém o ID da conta: copie-o para
# o backend.hcl e os tfvars LOCAIS (ignorados pelo Git), nunca para um
# arquivo versionado.
# =================================================================

output "state_bucket_name" {
  description = "Bucket dos estados, no namespace regional da conta (<projeto>-tfstate-<conta>-<região>-an). Vai em bucket = ... do backend.hcl de cada raiz e em state_bucket dos tfvars de cluster e k8s."
  value       = aws_s3_bucket.state.bucket
}

output "state_bucket_region" {
  description = "Região do bucket dos estados. Vai em region = ... do backend.hcl e em state_region dos tfvars de cluster e k8s."
  # Lida do próprio bucket depois de criado, e não da variável: é o valor
  # que o backend S3 realmente precisa para encontrar o bucket.
  value = aws_s3_bucket.state.bucket_region
}

output "github_oidc_provider_arn" {
  description = "ARN do provedor OIDC do GitHub. A raiz base o lê por data source para montar a trust das roles do CI e do self-healing."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "budget_name" {
  description = "Nome do Budget mensal, para conferir no console do Billing ou com aws budgets describe-budget."
  value       = aws_budgets_budget.monthly.name
}
