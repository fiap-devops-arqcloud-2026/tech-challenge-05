# syntax=docker/dockerfile:1
# =================================================================
# volunteer-service — imagem de produção (multi-stage)
# =================================================================
# Estágio 1 (build): baixa e compila as dependências como wheels.
# Estágio 2 (runtime): Python slim + wheels instaladas + código, rodando
# como usuário sem privilégios. pip, cache e arquivos de build não ficam
# na imagem final.
# =================================================================

# 3.13: versão estável com suporte longo e wheels para todas as dependências
# (conferido em 2026-11-20). O CI pode sobrescrever com --build-arg.
ARG PYTHON_VERSION=3.13

# -----------------------------------------------------------------
# Estágio 1 — build das wheels
# -----------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1
WORKDIR /build

# requirements primeiro: esta camada fica em cache enquanto ele não mudar.
COPY requirements.txt .
# Gera wheels de todas as dependências (inclusive as transitivas); o runtime
# instala a partir delas, sem compilador e sem acesso à internet.
RUN pip wheel --wheel-dir /wheels -r requirements.txt

# -----------------------------------------------------------------
# Estágio 2 — runtime
# -----------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim

# PYTHONDONTWRITEBYTECODE: não grava .pyc (o sistema de arquivos pode ser
# somente leitura no Kubernetes). PYTHONUNBUFFERED: logs saem na hora no
# stdout, sem buffer. PORT: lida pelo Gunicorn para o bind em 0.0.0.0:$PORT.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8083

# Aplica as atualizações de segurança do Debian publicadas depois da imagem
# base (em 2026-11-20, a correção do zlib1g apontada pelo Trivy) e limpa o
# cache do apt para não inchar a camada.
# Usuário e grupo com UID/GID numéricos fixos (10001): o Kubernetes só
# consegue verificar runAsNonRoot quando o USER da imagem é numérico.
RUN apt-get update \
    && apt-get upgrade --yes --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --home-dir /app app

WORKDIR /app

# As wheels entram por bind mount do estágio 1: não viram camada da imagem.
# Depois de instalar, o próprio pip sai da imagem: o runtime não precisa dele,
# e as cópias que ele embute (msgpack, pkg_resources) eram os únicos achados
# HIGH com correção apontados pelo Trivy na camada Python (2026-11-20).
RUN --mount=type=bind,from=build,source=/wheels,target=/wheels \
    pip install --no-index /wheels/*.whl \
    && python -m pip uninstall --yes pip

# Só o código de produção (testes e arquivos locais ficam no .dockerignore).
COPY app.py telemetry.py ./

USER 10001:10001
EXPOSE 8083

# Forma exec: o Gunicorn é o PID 1 e recebe o SIGTERM do Kubernetes
# diretamente (desligamento gracioso dos workers). Sem --preload: o cliente do
# DynamoDB e o SDK do OpenTelemetry nascem em cada worker, depois do fork.
# Sem --access-logfile: o próprio app registra cada requisição em JSON.
CMD ["gunicorn", "--workers", "2", "--graceful-timeout", "20", "app:app"]
