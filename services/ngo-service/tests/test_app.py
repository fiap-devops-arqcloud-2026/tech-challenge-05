"""Testes das rotas do ngo-service: as regras de negócio do código recebido."""
import sys

import psycopg2
import pytest
from psycopg2.extras import RealDictCursor

from conftest import import_app

NGO = {
    "name": "Anjos de Patas",
    "email": "contato@anjosdepatas.org",
    "cause": "Proteção Animal",
    "city": "Osasco",
}


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok", "service": "ngo-service"}


def test_pool_usa_realdictcursor(ngo_app):
    # A fábrica de cursores fica no pool para a instrumentação do psycopg2 funcionar.
    assert ngo_app.pool.kwargs["cursor_factory"] is RealDictCursor
    assert (ngo_app.pool.minconn, ngo_app.pool.maxconn) == (1, 10)


def test_cria_ong(client, db, ngo_app):
    db.rows = [{"id": 3, **NGO, "created_at": "2026-11-20T12:00:00+00:00"}]

    resp = client.post("/ngos", json=NGO)

    assert resp.status_code == 201
    assert resp.get_json()["id"] == 3
    query, params = db.executed[0]
    assert query.startswith("INSERT INTO ngos")
    assert params == (NGO["name"], NGO["email"], NGO["cause"], NGO["city"])
    assert db.commits == 1
    # A conexão sempre volta ao pool.
    assert ngo_app.pool.returned == ngo_app.pool.taken == 1


@pytest.mark.parametrize("faltando", ["name", "email", "cause", "city"])
def test_cria_ong_sem_campo_obrigatorio(client, db, faltando):
    payload = {k: v for k, v in NGO.items() if k != faltando}

    resp = client.post("/ngos", json=payload)

    assert resp.status_code == 400
    assert resp.get_json() == {"error": "Campos obrigatórios ausentes"}
    assert not db.executed


def test_cria_ong_corpo_nao_json(client, db):
    # Com o Werkzeug 3, corpo que não é JSON recebe 415 antes de chegar à rota.
    resp = client.post("/ngos", data="name=x", content_type="application/x-www-form-urlencoded")

    assert resp.status_code == 415
    assert not db.executed


def test_cria_ong_email_duplicado(client, db, ngo_app):
    db.fail_with = psycopg2.IntegrityError()

    resp = client.post("/ngos", json=NGO)

    assert resp.status_code == 409
    assert resp.get_json() == {"error": "E-mail já cadastrado"}
    assert db.rollbacks == 1
    assert ngo_app.pool.returned == 1


def test_cria_ong_erro_interno(client, db):
    db.fail_with = RuntimeError("falha simulada")

    resp = client.post("/ngos", json=NGO)

    assert resp.status_code == 500
    assert resp.get_json() == {"error": "Erro interno"}
    assert db.rollbacks == 1


def test_lista_ongs(client, db):
    db.rows = [{"id": 2, **NGO}, {"id": 1, **NGO, "email": "info@educamais.org"}]

    resp = client.get("/ngos")

    assert resp.status_code == 200
    assert [o["id"] for o in resp.get_json()] == [2, 1]
    assert db.executed[0][0] == "SELECT * FROM ngos ORDER BY id DESC"


def test_lista_ongs_erro_interno(client, db):
    db.fail_with = RuntimeError("falha simulada")

    resp = client.get("/ngos")

    assert resp.status_code == 500
    assert resp.get_json() == {"error": "Erro interno"}


def test_sem_database_url_encerra(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    try:
        with pytest.raises(SystemExit) as exc:
            import_app()
        assert exc.value.code == 1
    finally:
        sys.modules.pop("app", None)
