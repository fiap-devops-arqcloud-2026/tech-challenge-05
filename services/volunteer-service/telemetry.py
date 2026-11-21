"""Logs JSON e tracing OpenTelemetry dos serviços Python da SolidaryTech.

Adaptado da Fase 4 (flag-service/telemetry.py). O mesmo arquivo existe em
ngo-service e volunteer-service de propósito: cada serviço é um contexto de
build Docker independente e não enxerga pastas fora dele.

Princípios:
- Tracing é opt-in: só liga quando OTEL_EXPORTER_OTLP_ENDPOINT (ou
  OTEL_EXPORTER_OTLP_TRACES_ENDPOINT) está definido. Sem endpoint, nenhum SDK,
  thread ou exportação é criado e o serviço se comporta como o original.
- Logs sempre em JSON no stdout, com trace_id/span_id quando há span ativo:
  é o que liga uma linha de log no Loki ao trace no APM.
- Nada de dado do usuário em logs ou spans: sem corpo de requisição, sem
  parâmetros SQL, sem mensagem de exceção (só o tipo do erro).
- A configuração roda no worker do Gunicorn (não usar --preload): o SDK cria
  threads de exportação, e threads não sobrevivem ao fork do processo mestre.
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone

from flask import request
from opentelemetry import trace
from opentelemetry.propagate import set_global_textmap
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

SERVICE_NAMESPACE = "solidarytech"
# /health é chamado a cada poucos segundos pelas probes: fica fora dos traces
# e dos logs de requisição, senão só gera ruído (e custo no APM).
HEALTH_PATH = "/health"
HEALTH_EXCLUDED_URLS = r".*/health(?:\?.*)?$"

# Campos extras aceitos no log (extra={...}): lista fechada, para que nenhum
# dado inesperado vá parar no Loki por engano.
_EXTRA_FIELDS = (
    ("http.method", "http_method"),
    ("http.route", "http_route"),
    ("http.status_code", "http_status_code"),
    ("error.type", "error_type"),
)

# Estado do módulo: a configuração acontece uma única vez por processo.
_state = {"service_name": "", "provider": None, "configured": False}


class JsonFormatter(logging.Formatter):
    """Formata cada registro como uma linha JSON com campos controlados."""

    def format(self, record):
        document = {
            "time": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "service.name": _state["service_name"],
            "message": record.getMessage(),
        }
        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            document["trace_id"] = format(span_context.trace_id, "032x")
            document["span_id"] = format(span_context.span_id, "016x")
        for field, attribute in _EXTRA_FIELDS:
            value = getattr(record, attribute, None)
            if value is not None:
                document[field] = value
        return json.dumps(document, ensure_ascii=False)


def configure_telemetry(default_service_name, *, postgres=False, aws=False):
    """Configura logs JSON e, se houver endpoint OTLP, o tracing.

    postgres=True instrumenta o psycopg2; aws=True instrumenta o botocore
    (chamadas ao DynamoDB). Devolve o logger do serviço.
    """
    _state["service_name"] = os.getenv("OTEL_SERVICE_NAME", default_service_name)
    logger = logging.getLogger(default_service_name)
    if _state["configured"]:
        return logger
    _state["configured"] = True

    # Handler JSON no logger raiz: logs do app e das bibliotecas saem no
    # mesmo formato. Marcado para não ser duplicado se o módulo recarregar.
    root = logging.getLogger()
    if not any(getattr(h, "_solidarytech_json", False) for h in root.handlers):
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        handler._solidarytech_json = True  # pylint: disable=protected-access
        root.addHandler(handler)
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

    # Só o contexto W3C (traceparent/tracestate); baggage fica de fora porque
    # poderia carregar dados de usuário sem necessidade.
    set_global_textmap(TraceContextTextMapPropagator())

    endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") or os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if os.getenv("OTEL_SDK_DISABLED", "false").lower() == "true" or not endpoint:
        return logger

    # Imports tardios: sem endpoint, o SDK nem é carregado.
    # pylint: disable=import-outside-toplevel
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    provider = TracerProvider(resource=Resource.create({
        "service.name": _state["service_name"],
        "service.namespace": SERVICE_NAMESPACE,
    }))
    # Lote em segundo plano: a exportação não fica no caminho da requisição.
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    _state["provider"] = provider

    if postgres:
        from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
        # Sem parâmetros SQL nos spans (podem conter e-mail e nome) e sem
        # comentário SQL injetado nas queries.
        Psycopg2Instrumentor().instrument(
            tracer_provider=provider, capture_parameters=False, enable_commenter=False,
        )
    if aws:
        from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
        BotocoreInstrumentor().instrument(tracer_provider=provider)
    return logger


def instrument_flask(app):
    """Log JSON por requisição e, com tracing ligado, um span SERVER por rota.

    O log usa a rota-modelo (ex.: /volunteers/<int:ngo_id>), nunca o caminho
    real, que pode conter identificadores.
    """
    logger = logging.getLogger("http")

    @app.after_request
    def log_request(response):
        if request.path != HEALTH_PATH:
            route = request.url_rule.rule if request.url_rule else "unmatched"
            logger.info("http.request.completed", extra={
                "http_method": request.method,
                "http_route": route,
                "http_status_code": response.status_code,
            })
        return response

    if _state["provider"] is None:
        return

    # pylint: disable=import-outside-toplevel
    from opentelemetry.instrumentation.flask import FlaskInstrumentor
    FlaskInstrumentor().instrument_app(
        app,
        tracer_provider=_state["provider"],
        excluded_urls=HEALTH_EXCLUDED_URLS,
        enable_commenter=False,
    )
