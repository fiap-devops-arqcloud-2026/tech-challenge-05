# =================================================================
# MÓDULO RDS — uma instância PostgreSQL gerenciada
# =================================================================
# Adaptado do módulo da Fase 4, que criava uma instância por banco a
# partir de um mapa. Na Fase 5 é UMA instância com dois bancos lógicos
# (ngo_db e donation_db), criados depois pelo Job de schema, junto com
# um usuário por serviço. O que mudou, e por quê:
#
#   - sem db_name: o RDS cria só o banco padrão "postgres", de onde o Job
#     de schema cria os bancos e os usuários de cada serviço. Assim o
#     usuário mestre não vira credencial de aplicação;
#   - sem Secrets Manager: cada segredo custa por mês. A senha mestra
#     fica no estado do Terraform (bucket cifrado, acesso restrito) e
#     chega ao cluster como Secret do Kubernetes, criado pela raiz k8s;
#   - PostgreSQL 17, a mesma versão maior do Compose local;
#   - backup de 7 dias, que também é a janela do PITR usada pelo DR;
#   - db.t4g.micro (Graviton), mais barata que a db.t3.micro da Fase 4;
#   - security group sem regra de saída (ver abaixo).
# =================================================================

locals {
  # Porta padrão do PostgreSQL, usada no banco e na regra do firewall.
  port = 5432
}

# -----------------------------------------------------------------
# SENHA DO USUÁRIO MESTRE
# -----------------------------------------------------------------
# Gerada pelo próprio Terraform: ninguém digita, escolhe ou comita.
# -----------------------------------------------------------------

resource "random_password" "master" {
  # 24 caracteres alfanuméricos dão cerca de 143 bits de entropia.
  length = 24

  # Sem caracteres especiais, de propósito: a senha entra em URLs de
  # conexão (postgresql://usuario:senha@host/banco), e @, /, : ou # nela
  # quebrariam a URL com um erro de autenticação difícil de diagnosticar.
  # O RDS também recusa alguns deles (/, @, " e espaço) na senha mestra.
  special = false
}

# -----------------------------------------------------------------
# FIREWALL DO BANCO
# -----------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "PostgreSQL ${var.identifier}: entrada 5432 somente do security group do cluster EKS."
  vpc_id      = var.vpc_id

  # Sem bloco egress, de propósito. Ao criar o grupo, o Terraform remove
  # a regra de saída "tudo liberado" que a AWS coloca por padrão, e o
  # banco não precisa de outra: security group guarda estado, então a
  # resposta de uma conexão aceita na entrada sempre sai. A análise da
  # Fase 4 apontou a saída 0.0.0.0/0 daquele grupo como desnecessária.

  tags = {
    Name = "${var.identifier}-sg"
  }
}

# Regra em recurso próprio, como recomenda o provider: cada regra tem
# identificador e tags, e não há disputa entre regras em linha e
# separadas no mesmo grupo.
resource "aws_vpc_security_group_ingress_rule" "postgres_from_cluster" {
  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL a partir do security group do cluster EKS (nos e Pods)"

  ip_protocol = "tcp"
  from_port   = local.port
  to_port     = local.port

  # A origem é um GRUPO, e não um bloco de IPs: só o que está no security
  # group do cluster (os nós, e por eles os Pods) alcança o banco, mesmo
  # que outro recurso apareça na mesma VPC.
  referenced_security_group_id = var.allowed_security_group_id
}

# -----------------------------------------------------------------
# A INSTÂNCIA
# -----------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine = "postgres"
  # Só a versão maior (ex.: "17"). Com auto_minor_version_upgrade, o RDS
  # escolhe a versão menor e a atualiza sozinho; a versão em uso aparece
  # no atributo engine_version_actual.
  engine_version             = var.engine_version
  auto_minor_version_upgrade = true

  # Ao fim do suporte padrão da versão maior, o RDS atualiza a versão em
  # vez de inscrever a instância no suporte estendido, que é cobrado por
  # vCPU-hora. Mesmo critério do upgrade_policy STANDARD do EKS.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  instance_class = var.instance_class

  allocated_storage = var.allocated_storage_gb
  # gp3: no RDS custa o mesmo por GiB que o gp2, mas um volume de 20 GiB
  # tem base de 3.000 IOPS, contra 100 IOPS (com créditos de rajada) do
  # gp2 do mesmo tamanho.
  storage_type = "gp3"
  # Criptografia em repouso, com a chave gerenciada aws/rds. Não pode ser
  # ligada depois sem recriar a instância (e perder os dados).
  storage_encrypted = true

  # Sem db_name: ver o cabeçalho.
  username = var.master_username
  password = random_password.master.result
  port     = local.port

  # Rede: sub-redes de banco da raiz base (sem rota para a internet) e o
  # firewall acima. Sem IP público: são duas barreiras independentes.
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  # Uma única AZ: Multi-AZ dobraria o custo da instância, e a proteção
  # dos dados vem dos backups com PITR.
  multi_az = false

  # Backups automáticos diários mais os logs de transação: permitem
  # restaurar o banco em qualquer ponto da janela de retenção (PITR).
  backup_retention_period = var.backup_retention_days
  # As tags obrigatórias (default_tags) seguem para os snapshots, o que
  # mantém o custo dos backups visível no filtro por tag.
  copy_tags_to_snapshot = true

  # Ambiente efêmero, destruído ao fim de cada janela de trabalho:
  #   - sem proteção contra exclusão, que faria o destroy falhar;
  #   - sem snapshot final, que sobraria cobrando depois do destroy;
  #   - backups automáticos apagados junto com a instância, pelo mesmo
  #     motivo (é o padrão do RDS; fica explícito para não surpreender).
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  # Mudanças de configuração valem na hora, sem esperar a janela de
  # manutenção (que pode cair fora da janela de trabalho).
  apply_immediately = true

  # Performance Insights e monitoramento avançado ficam desligados (os
  # padrões do RDS): a observabilidade da aplicação vem do APM e dos
  # spans do PostgreSQL emitidos pelos serviços.
}
