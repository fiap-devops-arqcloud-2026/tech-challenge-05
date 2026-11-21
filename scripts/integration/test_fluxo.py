#!/usr/bin/env python3
"""Teste de integração do ambiente local (Docker Compose).

Percorre o fluxo principal nos três serviços e confere que a doação chegou
à fila SQS do emulador. Usa só a biblioteca padrão do Python (roda igual na
máquina de quem desenvolve e no runner do CI).

Uso, com o Compose no ar:
    python3 scripts/integration/test_fluxo.py
    CHECK_TRACEPARENT=1 python3 scripts/integration/test_fluxo.py   # com docker-compose.otel.yaml

Sai com código 0 quando tudo passa e 1 na primeira falha.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

NGO_URL = os.getenv("NGO_URL", "http://localhost:8081")
DONATION_URL = os.getenv("DONATION_URL", "http://localhost:8082")
VOLUNTEER_URL = os.getenv("VOLUNTEER_URL", "http://localhost:8083")
MOTO_URL = os.getenv("MOTO_URL", "http://localhost:5000")
# A mesma URL e a mesma região que o donation-service recebe no Compose.
QUEUE_URL = os.getenv("SQS_QUEUE_URL", "http://moto:5000/123456789012/solidary-donations")
AWS_REGION = os.getenv("AWS_REGION", "us-east-2")
CHECK_TRACEPARENT = os.getenv("CHECK_TRACEPARENT") == "1"


class Falha(Exception):
    """Uma verificação do fluxo não passou."""


def call(method, url, body=None, headers=None):
    """Faz a requisição HTTP e devolve (status, corpo decodificado de JSON)."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:  # nosec B310 - URLs locais do teste
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        raw, status = error.read(), error.code
    try:
        return status, json.loads(raw) if raw else None
    except json.JSONDecodeError:
        return status, raw.decode(errors="replace")


def check(condition, message):
    if not condition:
        raise Falha(message)
    print(f"  ok  {message}")


def receive_sqs_messages():
    """Lê mensagens da fila no Moto pelo protocolo JSON da SQS (sem SDK).

    O Moto não confere assinatura, mas tira a região do escopo da credencial
    no cabeçalho Authorization; sem ele, procuraria a fila em us-east-1.
    """
    status, body = call(
        "POST",
        MOTO_URL,
        {"QueueUrl": QUEUE_URL, "MaxNumberOfMessages": 10, "MessageAttributeNames": ["All"], "WaitTimeSeconds": 1},
        headers={
            "X-Amz-Target": "AmazonSQS.ReceiveMessage",
            "Content-Type": "application/x-amz-json-1.0",
            "Authorization": f"AWS4-HMAC-SHA256 Credential=local/20260101/{AWS_REGION}/sqs/aws4_request, "
                             "SignedHeaders=host, Signature=teste-local",
        },
    )
    if status != 200:
        print(f"  ..  ReceiveMessage devolveu {status}: {body}")
        return []
    return (body or {}).get("Messages", []) if isinstance(body, dict) else []


def main():
    sufixo = uuid.uuid4().hex[:8]

    print("1. Saúde dos serviços")
    for nome, url in (("ngo", NGO_URL), ("donation", DONATION_URL), ("volunteer", VOLUNTEER_URL)):
        status, body = call("GET", f"{url}/health")
        check(status == 200 and body.get("status") == "ok", f"{nome}-service /health 200")

    print("2. ONGs (PostgreSQL ngo_db)")
    status, ngos = call("GET", f"{NGO_URL}/ngos")
    nomes = {n["name"] for n in ngos} if status == 200 else set()
    check({"Anjos de Patas", "Educa Mais"} <= nomes, "seed do coordenador presente em GET /ngos")
    nova = {"name": f"ONG Teste {sufixo}", "email": f"teste-{sufixo}@example.org", "cause": "Educação", "city": "São Paulo"}
    status, criada = call("POST", f"{NGO_URL}/ngos", nova)
    check(status == 201 and criada.get("id"), "POST /ngos devolve 201 com id")
    status, _ = call("POST", f"{NGO_URL}/ngos", nova)
    check(status == 409, "e-mail repetido devolve 409")
    status, _ = call("POST", f"{NGO_URL}/ngos", {"name": "incompleta"})
    check(status == 400, "payload incompleto devolve 400")

    print("3. Doações (PostgreSQL donation_db + SQS)")
    doacao = {"ngo_id": criada["id"], "amount": 25.5, "donor_name": f"Doador {sufixo}"}
    status, gravada = call("POST", f"{DONATION_URL}/donations", doacao)
    check(status == 201 and gravada.get("status") == "APPROVED", "POST /donations devolve 201 APPROVED")
    status, lista = call("GET", f"{DONATION_URL}/donations")
    check(status == 200 and any(d["id"] == gravada["id"] for d in lista), "doação aparece em GET /donations")

    mensagem = None
    for _ in range(10):  # a publicação é assíncrona: espera até ~10 s
        for msg in receive_sqs_messages():
            if json.loads(msg["Body"]).get("id") == gravada["id"]:
                mensagem = msg
        if mensagem:
            break
        time.sleep(1)
    check(mensagem is not None, "evento da doação chegou à fila SQS")
    evento = json.loads(mensagem["Body"])
    check(evento["donor_name"] == doacao["donor_name"] and evento["status"] == "APPROVED",
          "corpo do evento é o JSON da doação (contrato preservado)")
    if CHECK_TRACEPARENT:
        traceparent = mensagem.get("MessageAttributes", {}).get("traceparent", {}).get("StringValue", "")
        check(traceparent.startswith("00-"), "mensagem leva o traceparent W3C nos atributos")

    print("4. Voluntários (DynamoDB)")
    voluntario = {"name": f"Voluntária {sufixo}", "email": f"vol-{sufixo}@example.org", "ngo_id": criada["id"]}
    status, registrado = call("POST", f"{VOLUNTEER_URL}/volunteers", voluntario)
    check(status == 201 and registrado.get("volunteer_id"), "POST /volunteers devolve 201 com volunteer_id")
    status, da_ong = call("GET", f"{VOLUNTEER_URL}/volunteers/{criada['id']}")
    check(status == 200 and any(v["volunteer_id"] == registrado["volunteer_id"] for v in da_ong),
          "voluntário aparece em GET /volunteers/<ngo_id>")

    print("Fluxo completo: OK")


if __name__ == "__main__":
    try:
        main()
    except (Falha, KeyError, TypeError, urllib.error.URLError) as erro:
        print(f"FALHOU: {erro}", file=sys.stderr)
        sys.exit(1)
