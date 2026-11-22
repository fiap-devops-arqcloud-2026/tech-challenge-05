# =================================================================
# MÓDULO IAM-CI — saídas
# =================================================================
# Os ARNs das roles não são segredo: sem um token OIDC emitido para a
# branch autorizada deste repositório, o ARN sozinho não dá acesso a nada.
# =================================================================

output "ci_role_arn" {
  description = "ARN da role do CI, usado em role-to-assume da action aws-actions/configure-aws-credentials."
  value       = aws_iam_role.ci.arn
}

output "ci_role_name" {
  description = "Nome da role do CI, útil em consultas pela AWS CLI."
  value       = aws_iam_role.ci.name
}

output "self_healing_role_arn" {
  description = "ARN da role do self-healing. A raiz cluster cria o access entry do EKS para ela, e o workflow de self-healing a assume."
  value       = aws_iam_role.self_healing.arn
}

output "self_healing_role_name" {
  description = "Nome da role do self-healing, útil em consultas pela AWS CLI."
  value       = aws_iam_role.self_healing.name
}

output "github_oidc_subject" {
  description = "Subject exato aceito pela trust das duas roles; ajuda a diagnosticar um AccessDenied no workflow."
  value       = local.github_oidc_subject
}
