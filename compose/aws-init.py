"""Cria a fila SQS e a tabela DynamoDB no emulador local (Moto).

É o equivalente local do que o Terraform cria na AWS, com os mesmos nomes e a
mesma chave da tabela descritos no README do coordenador. Idempotente: pode
rodar de novo sem erro. Usa o boto3 que já vem na imagem do Moto.
"""
import os
import sys

import boto3
from botocore.exceptions import ClientError

region = os.environ["AWS_REGION"]
queue_name = os.environ["SQS_QUEUE_NAME"]
table_name = os.environ["DYNAMODB_TABLE"]

# AWS_ENDPOINT_URL (http://moto:5000) é lido pelo boto3 automaticamente.
sqs = boto3.client("sqs", region_name=region)
dynamodb = boto3.client("dynamodb", region_name=region)

# Fila Standard (a mesma do README do coordenador). create_queue devolve a URL
# da fila existente quando ela já foi criada com os mesmos atributos.
queue_url = sqs.create_queue(QueueName=queue_name)["QueueUrl"]
print(f"fila pronta: {queue_url}")

try:
    dynamodb.create_table(
        TableName=table_name,
        KeySchema=[{"AttributeName": "volunteer_id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "volunteer_id", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )
    print(f"tabela criada: {table_name}")
except ClientError as error:
    if error.response["Error"]["Code"] != "ResourceInUseException":
        print(f"falha ao criar a tabela: {error.response['Error']['Code']}", file=sys.stderr)
        raise
    print(f"tabela já existia: {table_name}")
