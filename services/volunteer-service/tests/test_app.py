"""Testes das rotas do volunteer-service: as regras de negócio do código recebido."""
import sys
import uuid

import pytest

from conftest import import_app

VOLUNTEER = {"name": "Carla", "email": "carla@example.org", "ngo_id": 1}


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok", "service": "volunteer-service"}


def test_cadastra_voluntario(client, volunteer_app):
    resp = client.post("/volunteers", json=VOLUNTEER)

    assert resp.status_code == 201
    item = resp.get_json()
    uuid.UUID(item["volunteer_id"])  # id gerado pelo serviço, formato UUID
    assert item["name"] == "Carla"
    assert item["ngo_id"] == 1
    assert item["registered_at"].isdigit()
    # O item foi gravado na tabela.
    stored = volunteer_app.table.get_item(Key={"volunteer_id": item["volunteer_id"]})["Item"]
    assert stored["email"] == "carla@example.org"


@pytest.mark.parametrize("faltando", ["name", "email", "ngo_id"])
def test_cadastra_sem_campo_obrigatorio(client, faltando):
    payload = {k: v for k, v in VOLUNTEER.items() if k != faltando}

    resp = client.post("/volunteers", json=payload)

    assert resp.status_code == 400
    assert resp.get_json() == {"error": "Campos obrigatórios ausentes"}


def test_lista_voluntarios_da_ong(client):
    client.post("/volunteers", json=VOLUNTEER)
    client.post("/volunteers", json={**VOLUNTEER, "name": "Davi", "email": "davi@example.org"})
    client.post("/volunteers", json={**VOLUNTEER, "name": "Eva", "ngo_id": 2})

    resp = client.get("/volunteers/1")

    assert resp.status_code == 200
    nomes = sorted(v["name"] for v in resp.get_json())
    assert nomes == ["Carla", "Davi"]
    # Comportamento herdado: o DynamoDB devolve números como Decimal, que o
    # Flask serializa como texto no GET.
    assert {v["ngo_id"] for v in resp.get_json()} == {"1"}


def test_lista_vazia(client):
    resp = client.get("/volunteers/99")
    assert resp.status_code == 200
    assert resp.get_json() == []


def test_sem_tabela_encerra(aws_env, monkeypatch):  # pylint: disable=unused-argument
    monkeypatch.delenv("AWS_DYNAMODB_TABLE", raising=False)
    try:
        with pytest.raises(SystemExit) as exc:
            import_app()
        assert exc.value.code == 1
    finally:
        sys.modules.pop("app", None)
