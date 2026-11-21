"""Fixtures do ngo-service: o PostgreSQL é substituído por um pool falso.

O app.py cria o pool de conexões no import (como no código original). Por
isso cada teste troca o SimpleConnectionPool por um FakePool antes de
importar o módulo, e o remove de sys.modules no fim.
"""
import importlib
import sys

import pytest


class FakeCursor:
    """Cursor mínimo: registra a query e devolve as linhas configuradas."""

    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, query, params=None):
        self.conn.executed.append((query, params))
        if self.conn.fail_with is not None:
            raise self.conn.fail_with

    def fetchone(self):
        return self.conn.rows[0] if self.conn.rows else None

    def fetchall(self):
        return list(self.conn.rows)


class FakeConnection:
    """Conexão falsa: guarda queries, commits e rollbacks."""

    def __init__(self):
        self.executed = []
        self.rows = []
        self.fail_with = None
        self.commits = 0
        self.rollbacks = 0

    def cursor(self):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


class FakePool:
    """Substitui o SimpleConnectionPool e guarda os argumentos recebidos."""

    def __init__(self, minconn, maxconn, **kwargs):
        self.minconn, self.maxconn, self.kwargs = minconn, maxconn, kwargs
        self.conn = FakeConnection()
        self.taken = 0
        self.returned = 0

    def getconn(self):
        self.taken += 1
        return self.conn

    def putconn(self, conn):
        assert conn is self.conn
        self.returned += 1


def import_app():
    """Importa o app.py do zero (o módulo roda a configuração no import)."""
    sys.modules.pop("app", None)
    return importlib.import_module("app")


@pytest.fixture
def ngo_app(monkeypatch):
    """app.py importado com DATABASE_URL fictícia, pool falso e sem tracing."""
    monkeypatch.setenv("DATABASE_URL", "postgresql://teste:teste@localhost:5432/ngo_db")
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_ENDPOINT", raising=False)
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", raising=False)
    monkeypatch.setattr("psycopg2.pool.SimpleConnectionPool", FakePool)
    module = import_app()
    yield module
    sys.modules.pop("app", None)


@pytest.fixture
def client(ngo_app):
    return ngo_app.app.test_client()


@pytest.fixture
def db(ngo_app):
    return ngo_app.pool.conn
