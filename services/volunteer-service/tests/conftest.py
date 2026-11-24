"""Fixtures do volunteer-service: o DynamoDB é simulado pelo Moto.

O app.py cria o cliente do DynamoDB no import (como no código original). Por
isso cada teste liga o Moto, cria a tabela e só então importa o módulo.
"""
import importlib
import sys

import boto3
import pytest
from moto import mock_aws

TABLE = "SolidaryTechVolunteers"
REGION = "us-east-2"


def import_app():
    """Importa o app.py do zero (o módulo roda a configuração no import)."""
    sys.modules.pop("app", None)
    return importlib.import_module("app")


@pytest.fixture
def aws_env(monkeypatch):
    """Variáveis do serviço com credenciais falsas: o Moto intercepta tudo."""
    monkeypatch.setenv("AWS_DYNAMODB_TABLE", TABLE)
    monkeypatch.setenv("AWS_REGION", REGION)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)
    monkeypatch.delenv("AWS_PROFILE", raising=False)
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_ENDPOINT", raising=False)
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", raising=False)


@pytest.fixture
def volunteer_app(aws_env):  # pylint: disable=unused-argument,redefined-outer-name
    with mock_aws():
        # Mesma chave da tabela descrita no README do coordenador.
        boto3.client("dynamodb", region_name=REGION).create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "volunteer_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "volunteer_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        module = import_app()
        yield module
    sys.modules.pop("app", None)


@pytest.fixture
def client(volunteer_app):  # pylint: disable=redefined-outer-name
    return volunteer_app.app.test_client()
