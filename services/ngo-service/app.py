"""ngo-service — cadastro das ONGs parceiras da SolidaryTech.

Código recebido do repositório oficial do Hackathon. Rotas, payloads, regras
de negócio e variáveis de ambiente foram mantidos. Mudanças de engenharia de
plataforma (detalhes no README.md do serviço):
- logs estruturados em JSON, com trace_id (telemetry.py);
- tracing OpenTelemetry opcional (Flask e psycopg2), ligado só com endpoint OTLP;
- RealDictCursor definido no pool, e não em cada cursor: a instrumentação do
  psycopg2 troca a fábrica de cursores da conexão, e sobrescrevê-la no
  cursor descartaria o span da query;
- erros registram só o tipo da exceção, sem detalhes da conexão.
"""
import os
import sys

import psycopg2
from dotenv import load_dotenv
from flask import Flask, request, jsonify
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool

from telemetry import configure_telemetry, instrument_flask

load_dotenv()

# Logs e tracing antes do pool: a instrumentação do psycopg2 precisa estar
# ativa quando as conexões nascem. Roda no worker do Gunicorn (sem --preload).
log = configure_telemetry("ngo-service", postgres=True)

app = Flask(__name__)
instrument_flask(app)

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("Erro: DATABASE_URL não definida.")
    sys.exit(1)

try:
    pool = SimpleConnectionPool(1, 10, dsn=DATABASE_URL, cursor_factory=RealDictCursor)
    log.info("Pool de conexões com o PostgreSQL (ngo-service) inicializado.")
except Exception as e:  # pylint: disable=broad-exception-caught
    # Só o tipo do erro: a mensagem do driver pode trazer host e usuário.
    log.critical("Erro ao conectar ao PostgreSQL.", extra={"error_type": type(e).__name__})
    sys.exit(1)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "ngo-service"})


@app.route('/ngos', methods=['POST'])
def create_ngo():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'cause', 'city')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    conn = pool.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO ngos (name, email, cause, city) VALUES (%s, %s, %s, %s) RETURNING *",
                (data['name'], data['email'], data['cause'], data['city'])
            )
            new_ngo = cur.fetchone()
            conn.commit()
            return jsonify(new_ngo), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        return jsonify({"error": "E-mail já cadastrado"}), 409
    except Exception as e:  # pylint: disable=broad-exception-caught
        conn.rollback()
        log.error("Erro ao criar ONG.", extra={"error_type": type(e).__name__})
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route('/ngos', methods=['GET'])
def get_ngos():
    conn = pool.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM ngos ORDER BY id DESC")
            return jsonify(cur.fetchall()), 200
    except Exception as e:  # pylint: disable=broad-exception-caught
        log.error("Erro ao buscar ONGs.", extra={"error_type": type(e).__name__})
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


if __name__ == '__main__':
    # Execução direta só para desenvolvimento; no contêiner o Gunicorn faz o bind.
    port = int(os.getenv("PORT", "8081"))
    app.run(host='0.0.0.0', port=port)  # nosec B104

