"""Testes do telemetry.py: formato JSON dos logs e correlação com o trace."""
import json
import logging

from opentelemetry.sdk.trace import TracerProvider

import telemetry


def _record(**extra):
    record = logging.LogRecord("teste", logging.INFO, __file__, 1, "evento %s", ("ok",), None)
    for key, value in extra.items():
        setattr(record, key, value)
    return record


def test_log_json_com_campos_controlados():
    linha = telemetry.JsonFormatter().format(
        _record(http_route="/ngos", http_status_code=201, senha="nao-deve-sair")
    )
    doc = json.loads(linha)

    assert doc["message"] == "evento ok"
    assert doc["level"] == "INFO"
    assert doc["http.route"] == "/ngos"
    assert doc["http.status_code"] == 201
    assert "nao-deve-sair" not in linha  # só campos da lista fechada
    assert "trace_id" not in doc  # sem span ativo


def test_log_json_leva_trace_id_do_span_ativo():
    tracer = TracerProvider().get_tracer("teste")
    with tracer.start_as_current_span("operacao") as span:
        doc = json.loads(telemetry.JsonFormatter().format(_record()))

    assert doc["trace_id"] == format(span.get_span_context().trace_id, "032x")
    assert doc["span_id"] == format(span.get_span_context().span_id, "016x")


def test_sem_endpoint_nao_liga_tracing(ngo_app):  # pylint: disable=unused-argument
    assert telemetry._state["provider"] is None  # pylint: disable=protected-access


def test_log_por_requisicao_ignora_health(client, db, caplog):
    db.rows = []
    with caplog.at_level(logging.INFO, logger="http"):
        client.get("/health")
        client.get("/ngos")

    registros = [r for r in caplog.records if r.name == "http"]
    assert len(registros) == 1
    assert registros[0].http_route == "/ngos"
    assert registros[0].http_method == "GET"
    assert registros[0].http_status_code == 200
