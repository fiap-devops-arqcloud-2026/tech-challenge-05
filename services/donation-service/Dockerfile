# syntax=docker/dockerfile:1
# =================================================================
# donation-service — imagem de produção (multi-stage)
# =================================================================
# Estágio 1 (build): compila um binário estático com o toolchain do Go.
# Estágio 2 (runtime): Alpine mínimo, só com o binário, os certificados TLS
# e um usuário sem privilégios. Compilador, código-fonte e cache de módulos
# ficam no estágio 1 e não chegam à imagem final (menos tamanho e menos
# superfície de ataque para o scan de vulnerabilidades).
# =================================================================

# Versões em um só lugar; o CI pode sobrescrever com --build-arg.
# O go.mod exige Go >= 1.26 (dependências do OpenTelemetry e x/crypto);
# 1.27 é a versão estável mais recente com suporte (conferida em 2026-11-20).
ARG GO_VERSION=1.27
ARG ALPINE_VERSION=3.24

# -----------------------------------------------------------------
# Estágio 1 — build
# -----------------------------------------------------------------
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

# Dependências primeiro: esta camada fica em cache enquanto go.mod e go.sum
# não mudarem, e o rebuild depois de mexer só no código fica rápido.
# "go mod verify" confere os hashes do go.sum (cadeia de suprimentos).
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Só o código de produção (os *_test.go ficam de fora pelo .dockerignore).
COPY *.go ./

# CGO_ENABLED=0  binário estático: não depende da libc da imagem final.
# -trimpath      remove os caminhos da máquina de build do binário.
# -ldflags -s -w remove tabela de símbolos e informação de debug (menor).
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/donation-service .

# -----------------------------------------------------------------
# Estágio 2 — runtime
# -----------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

# apk upgrade: aplica correções de segurança publicadas depois da imagem base.
# ca-certificates: TLS para a AWS (SQS) e para o endpoint OTLP.
# Usuário e grupo com UID/GID numéricos fixos (10001): o Kubernetes só
# consegue verificar runAsNonRoot quando o USER da imagem é numérico.
RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app

WORKDIR /app
COPY --from=build /out/donation-service /app/donation-service

USER 10001:10001

# Porta documentada; a real vem da variável PORT (padrão 8082 no código).
EXPOSE 8082

# Forma exec: o binário é o PID 1 e recebe o SIGTERM do Kubernetes
# diretamente, o que aciona o desligamento gracioso.
ENTRYPOINT ["/app/donation-service"]
