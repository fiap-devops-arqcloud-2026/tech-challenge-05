# Organização de pastas

TL;DR: Monorepo dividido por responsabilidade. Hoje existem `services/`, `compose/`, `docs/`, `scripts/` e `00_COLAB_IA/`; `terraform/`, `.github/workflows/` e `gitops/` nascem nas camadas C2 a C4. Não criar pastas vazias "para depois".

Última atualização: 2026-11-20, Claude.

## Estrutura

| Caminho | Uso | Camada |
|---|---|---|
| `README.md` | Apresentação pública do projeto (sem nomes de agentes nem IDs internos) | C0 |
| `AGENTS.md`, `.claude/CLAUDE.md` | Portas de entrada do Codex e do Claude; apontam para `00_COLAB_IA/` | C0 |
| `POSTECH - DCLT - Hackathon - Fase 5.pdf` | Enunciado oficial, somente leitura | — |
| `docs/enunciado/` | README do coordenador, cópia byte a byte, somente leitura | C0 |
| `docs/aulas-fiap/<módulo>/` | PDFs das aulas (somente leitura) e `GUIA-ESTUDO-*.html` | — |
| `docs/requisitos/` | Mapa de requisitos (`README.md` e `REQUISITOS.html`) | — |
| `docs/*.md` | Documentação técnica e de entrega (arquitetura, CI/CD, SRE, FinOps, ITSM, PCN) | C2–C10 |
| `docs/evidencias/`, `docs/relatorio/`, `docs/gravacao/` | Prints revisados, relatório PDF e roteiro do vídeo | C10 |
| `services/<svc>/` | Código de cada serviço, Dockerfile, testes e README | C1 |
| `docker-compose.yaml` | Ambiente local completo (PostgreSQL, Moto, serviços) | C1 |
| `docker-compose.otel.yaml` | Sobreposição com o OpenTelemetry Collector local (spans no log) | C1 |
| `compose/` | Apoio do Compose: init do PostgreSQL, criação da fila e da tabela no Moto, config do Collector local | C1 |
| `.env.example` | Valores locais e fictícios que o `.env` (ignorado) pode sobrescrever | C1 |
| `scripts/integration/`, `scripts/test-compose.sh` | Teste ponta a ponta do ambiente local (também usado no CI) | C1 |
| `terraform/` | Raízes `bootstrap/`, base (raiz), `cluster/`, `k8s/` e `modules/` | C2 |
| `.github/workflows/` | CI/CD DevSecOps, verificações e self-healing | C3, C8 |
| `gitops/` | Kustomize (`base/`, `overlays/prod/`) e Applications do ArgoCD (app e observabilidade) | C4, C5 |
| `scripts/` | Utilitários versionados (varredura de segredos, testes de integração, conferências) | C0+ |
| `00_COLAB_IA/` | Protocolo, plano, decisões, pendências, log e contexto da colaboração | C0 |
| `00_COLAB_IA/02_TRABALHO/` | Auxiliares e análises (`NOME_AAAA-MM-DD_vNN`) | — |
| `00_COLAB_IA/_ARQUIVO_MORTO/` | Versões substituídas, com DE-PARA (criar quando houver a primeira) | — |

## Regras

- Nomes auxiliares: descrição + data ISO + `_v01`. Entregáveis seguem o nome pedido pelo enunciado.
- Arquivos de texto em UTF-8 com fim de linha LF (`.gitattributes` e `.editorconfig`).
- Pastas ignoradas pelo Git não são lixo: podem guardar evidências locais. Limpar só o que estiver inventariado.
- Estados do Terraform, planos, `.env`, kubeconfig e chaves nunca entram no Git (`.gitignore`).
- HTML de documentação abre por duplo clique, sem servidor nem dependência de rede.
