#!/bin/sh
# =================================================================
# Schema dos bancos no RDS — roda no Job "db-schema" (hook PreSync do ArgoCD)
# =================================================================
# Substitui o "kubectl run psql" manual da Fase 4 (Regra de Ouro: nada de
# kubectl à mão). É idempotente: roda a cada sincronização do ArgoCD e só
# cria o que ainda não existe.
#
#   1. espera o PostgreSQL aceitar conexões;
#   2. cria os usuários ngo_app e donation_app, se faltarem, e (re)define a
#      senha deles com o valor do Secret "db-schema" (gerado pelo Terraform);
#   3. cria ngo_db e donation_db, cada um com o próprio dono, e deixa cada
#      usuário conectar só no seu banco (menor privilégio);
#   4. aplica o init.sql do coordenador em cada banco, conectado como o dono,
#      só se a tabela principal ainda não existir (o seed de ONGs não é
#      idempotente: rodar de novo violaria o e-mail único).
#
# Variáveis (do Secret "db-schema"): PGHOST, PGPORT, PGUSER e PGPASSWORD (o
# usuário mestre do RDS), PGSSLMODE, NGO_APP_PASSWORD e DONATION_APP_PASSWORD.
# Nenhuma senha é impressa: elas entram no psql como variáveis.
# =================================================================
set -eu

: "${PGHOST:?PGHOST ausente}" "${PGUSER:?PGUSER ausente}" "${PGPASSWORD:?PGPASSWORD ausente}"
: "${NGO_APP_PASSWORD:?NGO_APP_PASSWORD ausente}" "${DONATION_APP_PASSWORD:?DONATION_APP_PASSWORD ausente}"
export PGPORT="${PGPORT:-5432}"
# O RDS PostgreSQL exige TLS: sem isso a conexão é recusada.
export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT=10

# -----------------------------------------------------------------
# 1. Espera o banco (o RDS pode estar terminando de subir)
# -----------------------------------------------------------------
tentativas=0
until pg_isready --quiet --dbname=postgres; do
  tentativas=$((tentativas + 1))
  if [ "$tentativas" -ge 30 ]; then
    echo "PostgreSQL indisponível depois de ${tentativas} tentativas" >&2
    exit 1
  fi
  sleep 5
done
echo "PostgreSQL disponível em ${PGHOST}:${PGPORT}"

# -----------------------------------------------------------------
# 2 e 3. Usuários e bancos (conectado como o usuário mestre)
# -----------------------------------------------------------------
# \gexec executa o comando gerado pelo SELECT só quando ele devolve linha:
# é o jeito idempotente de criar role e banco no psql. CREATE DATABASE não
# roda dentro de transação, e o psql em modo padrão faz autocommit.
# O GRANT da role ao usuário atual é exigido para criar um banco com outro
# dono (no RDS o mestre não é superusuário de verdade).
psql --no-psqlrc -v ON_ERROR_STOP=1 --dbname=postgres \
  -v ngo_pw="$NGO_APP_PASSWORD" -v donation_pw="$DONATION_APP_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE ngo_app LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ngo_app')\gexec
SELECT 'CREATE ROLE donation_app LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'donation_app')\gexec
ALTER ROLE ngo_app PASSWORD :'ngo_pw';
ALTER ROLE donation_app PASSWORD :'donation_pw';
GRANT ngo_app TO CURRENT_USER;
GRANT donation_app TO CURRENT_USER;
SELECT 'CREATE DATABASE ngo_db OWNER ngo_app' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ngo_db')\gexec
SELECT 'CREATE DATABASE donation_db OWNER donation_app' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'donation_db')\gexec
REVOKE CONNECT ON DATABASE ngo_db FROM PUBLIC;
REVOKE CONNECT ON DATABASE donation_db FROM PUBLIC;
GRANT CONNECT ON DATABASE ngo_db TO ngo_app;
GRANT CONNECT ON DATABASE donation_db TO donation_app;
SQL
echo "usuários e bancos conferidos"

# -----------------------------------------------------------------
# 4. Schemas do coordenador (conectado como o dono de cada banco)
# -----------------------------------------------------------------
# aplicar_schema <banco> <usuário> <senha> <tabela principal> <arquivo .sql>
aplicar_schema() {
  banco="$1" usuario="$2" senha="$3" tabela="$4" arquivo="$5"
  existente="$(PGUSER="$usuario" PGPASSWORD="$senha" psql --no-psqlrc -tA --dbname="$banco" \
    -c "SELECT to_regclass('public.${tabela}')")"
  if [ "$existente" = "$tabela" ]; then
    echo "${banco}: tabela ${tabela} já existe, schema mantido"
  else
    PGUSER="$usuario" PGPASSWORD="$senha" psql --no-psqlrc -v ON_ERROR_STOP=1 --dbname="$banco" -f "$arquivo"
    echo "${banco}: schema aplicado a partir de $(basename "$arquivo")"
  fi
}

aplicar_schema ngo_db ngo_app "$NGO_APP_PASSWORD" ngos /schema/ngo_db.sql
aplicar_schema donation_db donation_app "$DONATION_APP_PASSWORD" donations /schema/donation_db.sql
echo "schema dos bancos concluído"
