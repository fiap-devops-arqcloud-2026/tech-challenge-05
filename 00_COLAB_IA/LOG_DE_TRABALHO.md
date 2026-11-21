# Log de trabalho

TL;DR: C0 (fundação e colaboração) concluída em 2026-11-20 21:15. Código do coordenador versionado sem alterações em `80a967f`; estrutura de colaboração, plano por camadas e decisões D-001 a D-015 no commit seguinte. Próximo: C1 (serviços e contêineres).

Última atualização: 2026-11-20, Claude.

Formato: entrada nova no topo, sem apagar as anteriores. Cada entrada termina com "Estado p/ próximo agente". Horários em America/Sao_Paulo (UTC-03:00).

## 2026-11-20 21:15 — Claude — C0 concluída: fundação do repositório e colaboração

Pedido: montar o projeto inteiro, só com os obrigatórios do mapa, com boas práticas de arquitetura cloud e DevOps, tudo comentado e documentado, mantendo o projeto atualizado para o Codex retomar a qualquer momento; trabalhar em camadas; não inventar dados e perguntar o que bloquear.
Feito:
- Respostas do usuário registradas em DECISOES (D-001 a D-015), com citação literal: conta da Fase 4 em modo liga/desliga; New Relic e Slack reaproveitados e PagerDuty em conta nova; DR pela Opção A (Velero); fluxo dev → PR → main como na Fase 4; README do coordenador movido para `docs/enunciado/`; Budget de US$ 50/mês. Escolhas técnicas do agente registradas para veto (D-009 a D-015).
- PR #1 (guias de estudo e mapa) já estava mesclado na `dev` pelo usuário (`4a6ef6b`); trabalho seguiu na `dev`.
- Commit `80a967f`: serviços e README do coordenador sem alterações (README movido byte a byte; SHA-256 `398fe05a…757e8756` antes e depois; HEAD do repositório oficial ainda `79f5c20`).
- Criados: `AGENTS.md`, `.claude/CLAUDE.md`, `00_COLAB_IA/` (LEIA-PRIMEIRO, PLANO_DE_ACAO com matriz dos 47 obrigatórios, PENDENCIAS, LOG, DECISOES, DOSSIE, ORGANIZACAO), `02_TRABALHO/MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md` (gerado do workflow de leitura da Fase 4: 4 leitores + cruzamento), README do projeto, `docs/enunciado/README.md`, `.gitignore`, `.gitattributes`, `.editorconfig`, `SECURITY.md` e `scripts/security-check.sh`.
Verificação: `git check-ignore` confirma `.env`, `*.tfstate`, `*.tfplan`, `backend.hcl`, `*.tfvars`, kubeconfig e `*.pem` ignorados, e os `*.example` versionáveis; `security-check.sh` sem achados; mapeamento sem IDs de conta, e-mails ou nomes (varredura por regex).
Ambiente local: Go 1.27.1, Python 3.15.2, Terraform 1.16.0, kubectl 1.36.1, AWS CLI 2.35.11 e Docker Compose 5.6.1 instalados; Docker Desktop parado; sem Helm, Trivy, golangci-lint, Node e make.
Não feito: nenhuma operação AWS (nem leitura). Commit da C0 e push na `origin/dev` feitos logo depois desta entrada.
Estado p/ próximo agente: começar a C1 pela primeira caixa de PENDENCIAS. Ligar o Docker Desktop antes da validação (P-001). Dependências desatualizadas do código recebido (Flask 2.2.2, Go 1.21, aws-sdk-go v1) seguem a D-009: atualizar só o que o build ou o Trivy exigirem, registrando o motivo.

## 2026-11-20 15:53–20:35 — Claude — Leitura da Fase 4 e cruzamento com os obrigatórios

Feito: workflow de leitura do `tech-challenge-04` (somente leitura) com quatro leitores (IaC, CI/CD e GitOps, observabilidade e incidentes, serviços e colaboração) e um cruzamento com os 47 obrigatórios. Resultado: 11 camadas, 12 dúvidas consolidadas (DU-01 a DU-12) e 30 riscos, convertidos no mapeamento de `02_TRABALHO/` e no PLANO_DE_ACAO. As dúvidas viraram perguntas ao usuário ou decisões técnicas registradas (tabela de resolução no início do mapeamento).
Estado p/ próximo agente: não repetir a leitura; usar o mapeamento como referência e conferir no código da Fase 4 antes de copiar qualquer trecho.

## 2026-11-20 — Claude — Guias de estudo da Fase 5 e mapa de requisitos

Feito: cinco guias de estudo (um por pasta de aulas) e o mapa de requisitos (`docs/requisitos/`: 47 obrigatórios, 46 bônus, 19 sugestões e 22 dúvidas para o tutor). Commit `7552369`, PR #1 para a `dev`, mesclado pelo usuário (`4a6ef6b`).
Estado p/ próximo agente: material de estudo concluído; não faz parte das camadas de implementação.
