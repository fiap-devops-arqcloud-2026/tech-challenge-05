# Dossiê de contexto

TL;DR: O que é preciso saber para trabalhar no projeto sem reler tudo: o desafio, os três serviços como foram recebidos, contas e ferramentas disponíveis e os números de referência da Fase 4 (com data, só como referência).

Última atualização: 2026-11-20, Claude.

## O desafio (enunciado, `POSTECH - DCLT - Hackathon - Fase 5.pdf`)

A ONG fictícia SolidaryTech recebeu três microsserviços e precisa de uma plataforma confiável, observável, barata e resiliente. Cinco frentes, todas com itens obrigatórios (detalhe no [mapa de requisitos](../docs/requisitos/README.md)):

| Frente | O que se espera | Páginas |
|---|---|---|
| 0 — Fundação DevOps | Docker, EKS, Terraform de tudo, CI/CD com testes, SAST/SCA e build de imagem, GitOps (ArgoCD), observabilidade completa, APM com tracing, automações de incidente | p. 2–4 |
| 1 — SRE | ≥ 2 SLIs do donation-service, um SLO por SLI, dashboard SRE de SLO e error budget, MTTR no relatório | p. 4 |
| 2 — FinOps | Tags `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core`; rightsizing via GitOps; Forecast mensal; ≥ 1 recomendação nativa | p. 4–5 |
| 3 — ITSM e AIOps | IA do APM detectando anomalias; ciclo de vida do incidente desenhado | p. 5 |
| 4 — Multicloud, Segurança e DR | PCN executivo; RTO e RPO das doações; Opção A (Velero) ou B (ambiente espelho) | p. 5 |
| Entregáveis | Repositório (IaC com tags, YAML com requests/limits, pipelines DevSecOps); vídeo de até 20 min (pitch + demo); relatório PDF com seções SRE, FinOps, Segurança e DR, ITSM/AIOps | p. 6–7 |

**Regra de Ouro (p. 2):** aplicar tudo das Fases 1 a 4; nada de deploy manual com `kubectl`, nada de infraestrutura clicada, nada de voo cego.

## Os três serviços como recebidos

Cópia idêntica do repositório oficial `dougls/hackathon-DCLT` (commit `79f5c20`, conferido em 2026-11-20). O README original está em [`docs/enunciado/README-coordenador.md`](../docs/enunciado/README-coordenador.md).

| Serviço | Stack | Dados | Porta | Rotas | Variáveis |
|---|---|---|---|---|---|
| `ngo-service` | Python, Flask 2.2.2, psycopg2-binary 2.9.5, gunicorn 20.1.0 | PostgreSQL `ngo_db` (tabela `ngos`, seed com 2 ONGs) | 8081 | `GET /health`, `POST /ngos`, `GET /ngos` | `PORT`, `DATABASE_URL` |
| `donation-service` | Go 1.21, pgx v4, aws-sdk-go v1 | PostgreSQL `donation_db` (tabela `donations`) + fila SQS Standard | 8082 | `GET /health`, `POST /donations`, `GET /donations` | `PORT`, `DATABASE_URL`, `AWS_REGION`, `AWS_SQS_URL` |
| `volunteer-service` | Python, Flask 2.2.2, boto3 1.26.50, gunicorn 20.1.0 | DynamoDB `SolidaryTechVolunteers` (PK `volunteer_id`, String) | 8083 | `GET /health`, `POST /volunteers`, `GET /volunteers/<ngo_id>` | `PORT`, `AWS_REGION` (padrão us-east-1), `AWS_DYNAMODB_TABLE` |

Observações sobre o código recebido (não mudam regra de negócio; tratadas na C1 conforme a D-009 e a D-016):
- **F-001:** o `go.mod` declara `github.com/jackc/pgx/v4/stdlib v4.18.3` como módulo (é um pacote do `pgx/v4`), e o Go recusa o arquivo inteiro: o donation-service não compila como veio. A Fase 4 teve o mesmo problema.
- **F-002:** `Flask==2.2.2` sem trava de Werkzeug: o pip instala o Werkzeug 3.1.9 e o Flask não importa (`ImportError: cannot import name 'url_quote'`, reproduzido em 2026-11-20). Os dois serviços Python não sobem como vieram.
- Sem Dockerfile, sem testes e sem `go.sum`.
- O donation-service é o hot path: grava a doação com status `APPROVED` (simulação de gateway) e publica um evento na SQS numa goroutine sem contexto; não trata SIGTERM.
- A SQS só é ativada se `AWS_SQS_URL` e `AWS_REGION` estiverem definidas; ninguém consome a fila.
- O volunteer-service filtra por `ngo_id` com `Scan` (comentário do coordenador: em produção seria um GSI).
- Os serviços não chamam uns aos outros; o README do coordenador cita ElastiCache, mas nenhum serviço usa cache (D-014).
- O README do coordenador usa us-east-1 nos exemplos; o projeto usa us-east-2 (D-003). Não inferir infraestrutura pelos exemplos.

## Contas e acessos

- **AWS:** conta pessoal da Fase 4 (final 6140), plano gratuito com créditos: US$ 126,45 em 2026-11-13, plano válido até 2027-04-20 ou até esgotar. Cota de 5 vCPU On-Demand em us-east-2 (Fase 4). Desde 2026-11-12 sem recursos cobrados do projeto (auditoria de 2026-11-13). Permanecem: o provedor OIDC do GitHub (importar, D-012), a VPC padrão e o Budget `togglemaster-creditos` (US$ 80, criado fora do Terraform na Fase 4). AWS CLI 2.35.11 instalada; perfil a confirmar (P-004).
- **GitHub:** organização `fiap-devops-arqcloud-2026`, repositório `tech-challenge-05`, **público**, branch padrão `main`, trabalho na `dev`. `gh` autenticado.
- **New Relic:** conta da Fase 4, região US; endpoint OTLP `otlp.nr-data.net` (D-004). Detecção de anomalias a conferir (P-005).
- **Slack:** workspace e canal da Fase 4 (webhook direto) (D-004).
- **PagerDuty:** conta nova, a criar pelo usuário (P-002).

## Ferramentas locais (2026-11-20)

Instaladas: Go 1.27.1, Python 3.15.2 (`py`), Terraform 1.16.0, kubectl 1.36.1 (com `kubectl kustomize`), AWS CLI 2.35.11, Docker Compose 5.6.1, `gh`. Docker Desktop instalado, mas parado às 21:00. Não instaladas: Helm, Kustomize standalone, Trivy, golangci-lint, Node e make — usar imagens de contêiner ou os jobs do CI.

## Referências da Fase 4 (só referência, não medição da Fase 5)

- Custo: estimativa de US$ 0,409/h com tudo ligado (Price List, us-east-2, 2026-11-04). Consumo real de 2026-11-09 a 2026-11-12: US$ 33,55 (EC2 14,97; EKS 7,83; NAT/EBS 5,40; RDS 3,31), coberto por créditos.
- EKS 1.34 com node group `m7i-flex.large`; o suporte padrão da 1.34 termina por volta de 2026-12-01, e o estendido custa US$ 0,60/h por cluster.
- Cadeia de incidente medida em 2026-11-11: falha → HTTP 200 em 2 min 50 s; alerta Firing → HTTP 200 em 48 s.
- Prometheus com retenção de 2 dias: insuficiente para janela formal de SLO.
- Detalhes, caminhos e pegadinhas: [mapeamento da Fase 4](02_TRABALHO/MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md).
