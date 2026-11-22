# =================================================================
# SECRETS DOS BANCOS
# =================================================================
# A dor do enunciado: "credenciais do banco passadas em arquivos de texto
# sem segurança". Aqui nenhuma senha passa por arquivo, chat ou Git:
#   - a senha MESTRE do RDS vem do estado da raiz cluster;
#   - as senhas dos usuários de APLICAÇÃO nascem aqui, aleatórias;
#   - todas chegam ao cluster como Secrets do Kubernetes, criados pelo
#     Terraform direto na API do EKS.
#
# Sem External Secrets nem Secrets Manager (custo): os valores ficam no
# estado do Terraform, num bucket privado, cifrado e só com TLS.
#
# MENOR PRIVILÉGIO NOS BANCOS: cada serviço conecta com um usuário
# próprio, dono só do seu banco. A senha mestre vai apenas para o Job de
# schema, que cria esses usuários; os serviços nunca a recebem.
#
# CONTRATO COM O GITOPS (nomes e chaves que os manifestos referenciam):
#   ngo-service-db       DATABASE_URL                -> ngo-service
#   donation-service-db  DATABASE_URL                -> donation-service
#   db-schema            PGHOST, PGPORT, PGUSER,
#                        PGPASSWORD, PGSSLMODE,
#                        NGO_APP_PASSWORD,
#                        DONATION_APP_PASSWORD       -> Job de schema
# =================================================================

locals {
  # Nomes fixos dos bancos e dos usuários de aplicação. O Job de schema
  # cria exatamente estes; mudar aqui exige mudar lá.
  ngo_db_name      = "ngo_db"
  ngo_db_user      = "ngo_app"
  donation_db_name = "donation_db"
  donation_db_user = "donation_app"
}

# -----------------------------------------------------------------
# Senhas dos usuários de aplicação
# -----------------------------------------------------------------
# Sem caracteres especiais: a senha vai dentro de uma URL de conexão, e
# @, / ou : quebrariam o parsing. 24 caracteres alfanuméricos ainda dão
# mais de 140 bits de entropia.
#
# Ficam estáveis no estado entre applies. Se esta raiz for destruída e
# recriada com o RDS de pé, as senhas mudam: por isso o Job de schema
# precisa DEFINIR a senha a cada execução (ALTER ROLE ... PASSWORD), e não
# só na criação do usuário.
# -----------------------------------------------------------------

resource "random_password" "ngo_app" {
  length  = 24
  special = false
}

resource "random_password" "donation_app" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------
# ngo-service (Python, psycopg2)
# -----------------------------------------------------------------
resource "kubernetes_secret_v1" "ngo_db" {
  metadata {
    name      = "ngo-service-db"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = "ngo-service" })
  }

  type = "Opaque"

  data = {
    # Esquema postgresql://, o mesmo do ambiente local (Compose).
    # sslmode=require: a senha não trafega em claro dentro da VPC, e o RDS
    # PostgreSQL 15+ já vem com rds.force_ssl ligado, recusando conexão
    # sem TLS.
    DATABASE_URL = format(
      "postgresql://%s:%s@%s:%s/%s?sslmode=require",
      local.ngo_db_user,
      random_password.ngo_app.result,
      local.rds_address,
      local.rds_port,
      local.ngo_db_name,
    )
  }
}

# -----------------------------------------------------------------
# donation-service (Go, pgx)
# -----------------------------------------------------------------
resource "kubernetes_secret_v1" "donation_db" {
  metadata {
    name      = "donation-service-db"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = "donation-service" })
  }

  type = "Opaque"

  data = {
    # Esquema postgres://, o mesmo do ambiente local; o pgx aceita os dois.
    DATABASE_URL = format(
      "postgres://%s:%s@%s:%s/%s?sslmode=require",
      local.donation_db_user,
      random_password.donation_app.result,
      local.rds_address,
      local.rds_port,
      local.donation_db_name,
    )
  }
}

# -----------------------------------------------------------------
# Job de schema (criado pelo GitOps)
# -----------------------------------------------------------------
# As variáveis PG* são lidas diretamente pelo psql e pela libpq: o Job
# conecta como usuário mestre sem montar URL nenhuma. As duas senhas de
# aplicação são as MESMAS dos DATABASE_URL acima (mesmos random_password),
# o que garante que o usuário criado pelo Job e o usado pelo serviço não
# divergem — divergência só apareceria em execução, como "password
# authentication failed".
# -----------------------------------------------------------------
resource "kubernetes_secret_v1" "db_schema" {
  metadata {
    name      = "db-schema"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = merge(local.app_common_labels, { "app.kubernetes.io/name" = "db-schema" })
  }

  type = "Opaque"

  data = {
    PGHOST     = local.rds_address
    PGPORT     = tostring(local.rds_port)
    PGUSER     = local.rds_master_username
    PGPASSWORD = local.rds_master_password
    PGSSLMODE  = "require"

    NGO_APP_PASSWORD      = random_password.ngo_app.result
    DONATION_APP_PASSWORD = random_password.donation_app.result
  }
}
