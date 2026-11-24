#!/usr/bin/env bash
# =================================================================
# Inicialização do PostgreSQL local (Docker Compose)
# =================================================================
# Cria os dois bancos do projeto e aplica em cada um o schema recebido do
# coordenador (services/<svc>/db/init.sql, montado em /schemas/<banco>.sql).
#
# Roda uma única vez, na primeira inicialização do volume, pelo mecanismo
# /docker-entrypoint-initdb.d da imagem oficial do PostgreSQL. Para rodar
# de novo: docker compose down -v (apaga o volume).
#
# Na AWS, o mesmo papel é de um Job no GitOps (sem kubectl manual).
# =================================================================
set -euo pipefail

for db in ngo_db donation_db; do
  # Cria o banco vazio, conectado ao banco administrativo "postgres".
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -c "CREATE DATABASE ${db};"
  # Aplica o schema (tabelas e o seed de ONGs) dentro do banco recém-criado.
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
    -f "/schemas/${db}.sql"
done
