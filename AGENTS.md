# AGENTS.md — instruções para agentes de código

TL;DR: Projeto SolidaryTech (Hackathon Fase 5, POSTECH DevOps e Arquitetura Cloud). Antes de qualquer ação, leia [`00_COLAB_IA/LEIA-PRIMEIRO.md`](00_COLAB_IA/LEIA-PRIMEIRO.md), depois a camada em andamento em [`00_COLAB_IA/PENDENCIAS_E_PROXIMOS_PASSOS.md`](00_COLAB_IA/PENDENCIAS_E_PROXIMOS_PASSOS.md) e o topo de [`00_COLAB_IA/LOG_DE_TRABALHO.md`](00_COLAB_IA/LOG_DE_TRABALHO.md).

Última atualização: 2026-11-20, Claude.

## Contexto rápido

- Três microsserviços recebidos do coordenador em `services/`: `ngo-service` (Python/Flask, PostgreSQL, porta 8081), `donation-service` (Go, PostgreSQL + SQS, porta 8082, hot path) e `volunteer-service` (Python/Flask, DynamoDB, porta 8083).
- Objetivo: operá-los na AWS (us-east-2) com Terraform, EKS, ArgoCD, observabilidade, SRE, FinOps, AIOps e DR, **só com os itens obrigatórios** do enunciado (D-001).
- O trabalho segue o [plano por camadas](00_COLAB_IA/PLANO_DE_ACAO.md) (C0 a C10). Decisões em [`00_COLAB_IA/DECISOES.md`](00_COLAB_IA/DECISOES.md).
- Idioma: português do Brasil em código comentado, documentos e mensagens de commit.

## Regras inegociáveis

1. **Segredos:** nunca escrever valor de chave, senha ou token em arquivo versionado, terminal, LOG ou chat. Eles ficam no `.env` local (ignorado). Antes de commitar, rode `bash scripts/security-check.sh` e revise o diff.
2. **Git:** nunca `git add .` nem `git add -A` — adicione arquivo por arquivo. Trabalhe na `dev`. Nunca `gh pr merge --delete-branch`. PR e merge na `main` só com autorização do usuário.
3. **AWS:** leitura pode; criar, alterar ou destruir só com autorização específica do usuário. Terraform sempre com `plan -out=<camada>.tfplan` e `apply <camada>.tfplan`, nunca apply interativo.
4. **Regra de Ouro do enunciado:** nada de `kubectl apply` manual, nada de recurso clicado no console, nada de serviço sem monitoramento.
5. **Não inventar dados:** medições levam data e fonte; metas (SLO, RTO, RPO, orçamento) são decididas pelo usuário. Dúvida que bloqueia vira pergunta ao usuário.
6. **Somente leitura:** o PDF do enunciado, `docs/enunciado/`, os PDFs de aula e o repositório `tech-challenge-04` (referência da Fase 4).
7. **Documentos públicos** (README, `docs/`, código) não citam agentes nem IDs internos (D-/P-); isso fica em `00_COLAB_IA/`.

## Ao terminar uma tarefa

- Marque a entrega em PENDENCIAS, atualize a matriz do PLANO_DE_ACAO e registre no topo do LOG (data, hora, agente, o que foi feito, verificação e "Estado p/ próximo agente").
- Se a tarefa fechar uma camada, faça um commit curado na `dev` (Conventional Commits, em português).

## Comandos úteis

```bash
# Varredura de segredos nos arquivos rastreados (rodar antes de cada commit)
bash scripts/security-check.sh
```

```bash
# Testes do donation-service (Go 1.26+; banco e SQS simulados)
cd services/donation-service && go vet ./... && go test ./...
```

```bash
# Testes de um serviço Python dentro de um contêiner descartável (não instala nada na máquina)
docker run --rm -v "$PWD/services/ngo-service:/src:ro" -w /tmp python:3.13-slim sh -c "cp -r /src svc && cd svc && pip install -q -r requirements-dev.txt && python -m pytest -q -p no:cacheprovider"
```

```bash
# Teste ponta a ponta local (Compose: PostgreSQL, Moto e os três serviços); WITH_OTEL=1 confere também os spans
bash scripts/test-compose.sh
```

No Windows (Git Bash), use `MSYS_NO_PATHCONV=1` antes do `docker run` com volume e `PYTHON="py -I"` antes do `test-compose.sh`. Os comandos do Terraform e do GitOps entram aqui nas camadas C2 a C4.
