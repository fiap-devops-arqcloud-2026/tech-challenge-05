# =================================================================
# VARIÁVEIS DE ENTRADA — módulo rds
# =================================================================
# Sem valores padrão, como nos demais módulos: os padrões do projeto e a
# justificativa de cada um ficam em terraform/cluster/variables.tf.
# =================================================================

variable "identifier" {
  description = "Identificador da instância RDS (padrão do projeto: <projeto>-postgres). Também nomeia o security group."
  type        = string

  validation {
    # Regra do RDS: até 63 caracteres, começando por letra, só letras
    # minúsculas, dígitos e hífen, sem hífen no fim nem dois seguidos.
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier)) && !endswith(var.identifier, "-") && !strcontains(var.identifier, "--")
    error_message = "O identificador aceita até 63 caracteres minúsculos, dígitos ou hífen, começando por letra, sem hífen no fim nem dois hífens seguidos."
  }
}

variable "vpc_id" {
  description = "VPC da raiz base, onde nasce o security group do banco."
  type        = string
}

variable "db_subnet_group_name" {
  description = "DB subnet group criado pela raiz base com as sub-redes de banco (sem rota para a internet)."
  type        = string
}

variable "allowed_security_group_id" {
  description = <<-EOT
    Único security group autorizado a abrir conexão na porta 5432: o do
    cluster EKS, presente nos nós. Origem por grupo, e não por CIDR, faz
    com que outro recurso na mesma VPC continue sem acesso ao banco.
  EOT
  type        = string
}

variable "engine_version" {
  description = "Versão MAIOR do PostgreSQL (ex.: 17). A menor fica com o RDS, que a atualiza sozinho."
  type        = string

  validation {
    # Só a versão maior. Com uma versão menor fixada, cada atualização
    # automática do RDS viraria diferença no próximo plano.
    condition     = can(regex("^[0-9]{2}$", var.engine_version))
    error_message = "Informe só a versão maior do PostgreSQL, como 17."
  }
}

variable "instance_class" {
  description = "Classe da instância RDS (ex.: db.t4g.micro)."
  type        = string
}

variable "allocated_storage_gb" {
  description = "Tamanho do armazenamento gp3, em GiB."
  type        = number

  validation {
    # 20 GiB é o mínimo do RDS para gp3.
    condition     = var.allocated_storage_gb >= 20 && floor(var.allocated_storage_gb) == var.allocated_storage_gb
    error_message = "O armazenamento precisa ser um inteiro de pelo menos 20 GiB (mínimo do gp3 no RDS)."
  }
}

variable "backup_retention_days" {
  description = "Dias de retenção dos backups automáticos; é também a janela da restauração para um ponto no tempo (PITR)."
  type        = number

  validation {
    # 0 desligaria o backup automático e, com ele, o PITR de que a
    # estratégia de DR depende. 35 é o máximo do RDS.
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35 && floor(var.backup_retention_days) == var.backup_retention_days
    error_message = "A retenção de backup precisa ser um inteiro de 1 a 35 dias (0 desligaria o PITR)."
  }
}

variable "master_username" {
  description = "Usuário mestre do PostgreSQL. Os usuários de cada serviço são criados depois pelo Job de schema."
  type        = string

  validation {
    # Regra do RDS para PostgreSQL: começa por letra, até 63 letras,
    # dígitos ou sublinhado. "rdsadmin" é o papel interno do próprio RDS.
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username)) && lower(var.master_username) != "rdsadmin"
    error_message = "O usuário mestre começa por letra, tem até 63 letras, dígitos ou sublinhado e não pode ser rdsadmin."
  }
}
