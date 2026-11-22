# =================================================================
# SAÍDAS — módulo irsa
# =================================================================

output "role_arns" {
  description = <<-EOT
    Mapa <ServiceAccount> = <ARN da role>. A raiz k8s grava cada ARN na
    anotação eks.amazonaws.com/role-arn da ServiceAccount correspondente.
    Um ARN errado não impede o Pod de subir: a falha só aparece em tempo
    de execução, com AccessDenied na primeira chamada à AWS.
  EOT
  value       = { for name, role in aws_iam_role.this : name => role.arn }
}

output "role_names" {
  description = "Mapa <ServiceAccount> = <nome da role>, para consultas na AWS CLI e no console."
  value       = { for name, role in aws_iam_role.this : name => role.name }
}
