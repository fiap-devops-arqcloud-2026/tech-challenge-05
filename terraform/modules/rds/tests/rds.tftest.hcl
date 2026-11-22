# =================================================================
# TESTE DO MÓDULO RDS — firewall, criptografia, backup e ciclo de vida
# =================================================================
# Prova, sem tocar na AWS, que:
#
#   1. a porta 5432 aceita só o security group do cluster EKS, sem CIDR,
#      e o grupo do banco não tem regra de saída;
#   2. o banco é PostgreSQL na versão maior pedida, privado, cifrado e
#      em gp3;
#   3. os backups (PITR) ficam ligados com a retenção pedida, e as tags
#      seguem para os snapshots;
#   4. nada impede o destroy do ambiente efêmero (sem proteção contra
#      exclusão, sem snapshot final);
#   5. a senha mestra é longa e sem caracteres especiais (segura numa
#      URL de conexão);
#   6. entradas inválidas são recusadas no plano.
#
# COMO RODA SEM AWS
# mock_provider troca o provider AWS por um falso, e command = apply só
# simula a criação. A senha vem do provider random real, que roda na
# própria máquina, sem rede.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/rds init -backend=false
#   terraform -chdir=terraform/modules/rds test
# =================================================================

mock_provider "aws" {}

variables {
  identifier                = "solidarytech-postgres"
  vpc_id                    = "vpc-0123456789abcdef0"
  db_subnet_group_name      = "solidarytech-vpc"
  allowed_security_group_id = "sg-0c1a2b3c4d5e6f701"
  engine_version            = "17"
  instance_class            = "db.t4g.micro"
  allocated_storage_gb      = 20
  backup_retention_days     = 7
  master_username           = "solidary_admin"
}

# -----------------------------------------------------------------
# 1. Firewall
# -----------------------------------------------------------------

run "firewall_so_do_cluster" {
  command = apply

  assert {
    condition     = aws_vpc_security_group_ingress_rule.postgres_from_cluster.referenced_security_group_id == "sg-0c1a2b3c4d5e6f701" && aws_vpc_security_group_ingress_rule.postgres_from_cluster.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.postgres_from_cluster.cidr_ipv6 == null && aws_vpc_security_group_ingress_rule.postgres_from_cluster.prefix_list_id == null
    error_message = "A entrada no banco deve vir só do security group do cluster EKS, sem bloco CIDR nem prefix list."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.postgres_from_cluster.ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.postgres_from_cluster.from_port == 5432 && aws_vpc_security_group_ingress_rule.postgres_from_cluster.to_port == 5432
    error_message = "A regra deve liberar só TCP 5432."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.postgres_from_cluster.security_group_id == aws_security_group.this.id && aws_db_instance.this.vpc_security_group_ids == toset([aws_security_group.this.id])
    error_message = "A regra deve estar no grupo do banco, e o banco deve usar só esse grupo."
  }

  assert {
    condition     = length(aws_security_group.this.egress) == 0 && length(aws_security_group.this.ingress) == 0
    error_message = "O grupo do banco não deve ter regras em linha: nenhuma saída, e a entrada só pela regra separada."
  }
}

# -----------------------------------------------------------------
# 2 a 4. A instância
# -----------------------------------------------------------------

run "instancia_postgres" {
  command = apply

  assert {
    condition     = aws_db_instance.this.engine == "postgres" && aws_db_instance.this.engine_version == "17" && aws_db_instance.this.auto_minor_version_upgrade == true
    error_message = "O banco deve ser PostgreSQL na versão maior pedida, com atualização automática da versão menor."
  }

  assert {
    condition     = aws_db_instance.this.instance_class == "db.t4g.micro" && aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.storage_type == "gp3" && aws_db_instance.this.storage_encrypted == true
    error_message = "O banco deve usar a classe pedida e armazenamento gp3 cifrado do tamanho pedido."
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false && aws_db_instance.this.multi_az == false && aws_db_instance.this.db_subnet_group_name == "solidarytech-vpc"
    error_message = "O banco deve ficar privado, em uma AZ, no subnet group de banco da base."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 7 && aws_db_instance.this.copy_tags_to_snapshot == true
    error_message = "Os backups automáticos (PITR) devem guardar 7 dias, e as tags devem seguir para os snapshots."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection == false && aws_db_instance.this.skip_final_snapshot == true && aws_db_instance.this.delete_automated_backups == true && aws_db_instance.this.apply_immediately == true
    error_message = "O banco efêmero não pode bloquear o destroy nem deixar snapshot cobrando depois dele."
  }

  assert {
    condition     = aws_db_instance.this.engine_lifecycle_support == "open-source-rds-extended-support-disabled"
    error_message = "O banco não deve entrar no suporte estendido pago do RDS."
  }

  assert {
    condition     = aws_db_instance.this.username == "solidary_admin" && aws_db_instance.this.password == random_password.master.result && aws_db_instance.this.manage_master_user_password == null
    error_message = "O usuário mestre deve ser o pedido, com a senha gerada pelo Terraform (sem Secrets Manager)."
  }

  assert {
    condition     = output.address == aws_db_instance.this.address && output.port == 5432 && output.master_username == "solidary_admin"
    error_message = "As saídas devem expor host, porta e usuário do banco."
  }
}

# -----------------------------------------------------------------
# 5. Senha mestra
# -----------------------------------------------------------------

run "senha_segura_para_url" {
  command = apply

  assert {
    condition     = random_password.master.length == 24 && random_password.master.special == false
    error_message = "A senha deve ter 24 caracteres e nenhum caractere especial."
  }

  assert {
    condition     = can(regex("^[A-Za-z0-9]{24}$", nonsensitive(random_password.master.result)))
    error_message = "A senha gerada deve ter só letras e dígitos, para não quebrar a URL de conexão."
  }
}

# -----------------------------------------------------------------
# 6. Entradas inválidas
# -----------------------------------------------------------------

run "versao_menor_fixada_e_recusada" {
  command = plan

  variables {
    engine_version = "17.6"
  }

  expect_failures = [var.engine_version]
}

run "backup_desligado_e_recusado" {
  command = plan

  variables {
    backup_retention_days = 0
  }

  expect_failures = [var.backup_retention_days]
}

run "disco_abaixo_do_minimo_e_recusado" {
  command = plan

  variables {
    allocated_storage_gb = 10
  }

  expect_failures = [var.allocated_storage_gb]
}

run "usuario_reservado_e_recusado" {
  command = plan

  variables {
    master_username = "rdsadmin"
  }

  expect_failures = [var.master_username]
}
