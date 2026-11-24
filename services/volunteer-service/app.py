"""volunteer-service — cadastro de voluntários da SolidaryTech.

Código recebido do repositório oficial do Hackathon. Rotas, payloads, regras
de negócio e variáveis de ambiente foram mantidos. Mudanças de engenharia de
plataforma (detalhes no README.md do serviço):
- logs estruturados em JSON, com trace_id (telemetry.py);
- tracing OpenTelemetry opcional (Flask e botocore, que cobre as chamadas
  ao DynamoDB), ligado só com endpoint OTLP;
- erros registram só o tipo da exceção.

Teste local: com o boto3 atual, a variável AWS_ENDPOINT_URL aponta o SDK para
um emulador (Moto) sem mudança de código; na AWS ela fica vazia.
"""
import os
import sys
import uuid
import time

import boto3
from flask import Flask, request, jsonify
from dotenv import load_dotenv

from telemetry import configure_telemetry, instrument_flask

load_dotenv()

# Logs e tracing antes de criar o cliente AWS: a instrumentação do botocore
# precisa estar ativa quando o cliente nasce. Roda no worker do Gunicorn.
log = configure_telemetry("volunteer-service", aws=True)

app = Flask(__name__)
instrument_flask(app)

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE")

if not DYNAMODB_TABLE:
    log.critical("Erro: AWS_DYNAMODB_TABLE não definida.")
    sys.exit(1)

try:
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
    table = dynamodb.Table(DYNAMODB_TABLE)
    log.info("Conectado à tabela DynamoDB: %s", DYNAMODB_TABLE)
except Exception as e:  # pylint: disable=broad-exception-caught
    log.critical("Falha ao conectar no DynamoDB.", extra={"error_type": type(e).__name__})
    sys.exit(1)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    volunteer_id = str(uuid.uuid4())
    item = {
        'volunteer_id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': int(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }

    try:
        table.put_item(Item=item)
        return jsonify(item), 201
    except Exception as e:  # pylint: disable=broad-exception-caught
        log.error("Erro ao salvar voluntário no DynamoDB.", extra={"error_type": type(e).__name__})
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    try:
        # Nota para avaliação dos alunos: Operação Scan simplificada para fins de desenvolvimento.
        # Em cenários complexos de produção, índices globais secundários (GSI) seriam exigidos.
        response = table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('ngo_id').eq(ngo_id)
        )
        return jsonify(response.get('Items', [])), 200
    except Exception as e:  # pylint: disable=broad-exception-caught
        log.error("Erro ao buscar dados no DynamoDB.", extra={"error_type": type(e).__name__})
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    # Execução direta só para desenvolvimento; no contêiner o Gunicorn faz o bind.
    port = int(os.getenv("PORT", "8083"))
    app.run(host='0.0.0.0', port=port)  # nosec B104
