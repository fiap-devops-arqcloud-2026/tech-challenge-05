# =================================================================
# SAÍDAS — módulo rds
# =================================================================
# A raiz k8s monta com estes valores os Secrets das aplicações e do Job
# de schema (DATABASE_URL, PGHOST, PGUSER e afins).
# =================================================================

output "identifier" {
  description = "Identificador da instância RDS."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "ARN da instância RDS (útil para a cópia de backups entre regiões do DR)."
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Hostname da instância, sem a porta (o atributo endpoint traria host:porta)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta do PostgreSQL."
  value       = aws_db_instance.this.port
}

output "engine_version_actual" {
  description = "Versão completa do PostgreSQL em uso (maior.menor), escolhida pelo RDS."
  value       = aws_db_instance.this.engine_version_actual
}

output "master_username" {
  description = "Usuário mestre do PostgreSQL."
  value       = aws_db_instance.this.username
}

output "master_password" {
  description = "Senha do usuário mestre. Sensível: o Terraform mostra (sensitive value) no plano e no apply."
  value       = random_password.master.result
  sensitive   = true
}

output "security_group_id" {
  description = "Security group do banco (entrada 5432 só do security group do cluster EKS)."
  value       = aws_security_group.this.id
}
