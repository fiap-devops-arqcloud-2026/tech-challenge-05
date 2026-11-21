# Decisões

TL;DR: D-001 a D-015 registradas em 2026-11-20, antes de qualquer código de infraestrutura. Escopo só obrigatório, conta e região da Fase 4 com ambiente efêmero, New Relic e Slack reaproveitados, PagerDuty em conta nova, DR pela Opção A (Velero), Budget de US$ 50/mês, README do coordenador em `docs/enunciado/`, fluxo dev → PR → main. D-016 (C1): versões de linguagem, imagens base e dependências dos serviços.

Última atualização: 2026-11-20, Claude.

Formato: contexto, decisão, alternativas, status. Quem decidiu aparece no título: "usuário" quando a resposta veio dele (citada entre aspas), "agente" quando é escolha técnica reversível, tomada com base no pedido e registrada para veto. Herança: IDs da Fase 4 levam o prefixo F4- (F4-D-018); os da Fase 3, F3-.

## D-016 — Versões dos serviços e das imagens (2026-11-20, agente)

Contexto: o código recebido não compila nem sobe como veio. O `go.mod` declara `github.com/jackc/pgx/v4/stdlib` como módulo e é recusado pelo Go (F-001); o `Flask==2.2.2` não importa com o Werkzeug 3 que o pip instala sem trava, com `ImportError: cannot import name 'url_quote'` (F-002, reproduzido em 2026-11-20). As versões antigas também têm vulnerabilidades conhecidas, e a Fase 4 teve o build barrado pelo Trivy por causa do `golang.org/x/crypto` antigo.
Decisão (aplicação da D-009; versões conferidas no PyPI, no proxy de módulos Go e no Docker Hub em 2026-11-20):
- Go: diretiva `go 1.26` (exigida pelas dependências), build com `golang:1.27-alpine` e runtime `alpine:3.24`; `x/crypto` 0.59.0, `x/text` 0.44.0, OpenTelemetry 1.47.0, `otelhttp` 0.72.0; `pgx` v4.18.3 → v5.13.0, porque o `pgproto3/v2` do v4 tem HIGH sem correção nessa linha (Trivy, 2026-11-20) e a troca é só o import do driver; `aws-sdk-go` v1.51.10 mantido.
- Python: `python:3.13-slim`; Flask 3.1.3, Werkzeug 3.1.9, gunicorn 27.0.1, psycopg2-binary 2.9.13, python-dotenv 1.2.4, boto3 1.44.8; OpenTelemetry 1.45.2 / instrumentações 0.66b2. Testes com pytest 9.2.0 e moto 5.2.5. O `pip` é removido da imagem final: o runtime não o usa, e as cópias que ele embute (msgpack, pkg_resources) eram os únicos HIGH com correção na camada Python.
- Política de scan: CRITICAL derruba o pipeline (como na Fase 4); HIGH com correção é corrigido; HIGH do sistema operacional sem correção publicada é registrado no LOG e revisto quando a imagem base atualizar.
- Local: PostgreSQL `postgres:17-alpine` (a mesma versão maior será usada no RDS), Moto 5.2.5 e Collector `otel/opentelemetry-collector-contrib:0.163.2` (o mesmo da Fase 4).
- Usuário não root com UID/GID 10001 nas três imagens.
Alternativas: travar as versões antigas (Werkzeug < 3, como na Fase 4), mantendo vulnerabilidades conhecidas; migrar o `aws-sdk-go` para a v2 (mais código mudado sem exigência do scan).
Status: vigente. O resultado do Trivy nas imagens fica no LOG da C1.

## D-015 — Nomes e tags (2026-11-20, agente)

Contexto: o enunciado exige as tags `Project=SolidaryTech`, `Environment=Production` e `CostCenter=NGO-Core` (REQ-OBR-19). A Fase 4 usava o prefixo `togglemaster`.
Decisão: prefixo de recursos e namespace Kubernetes `solidarytech`. Tags obrigatórias exatamente como no enunciado, mais `ManagedBy=Terraform`, aplicadas por `default_tags` em todos os providers AWS (inclusive o da região secundária). Chaves de estado com o prefixo `phase5/prod/`.
Alternativas: tags extras como `Owner` ou `Repository` (adiadas; cada tag a mais é mais um item a conferir).
Status: vigente; aplicada a partir da C2.

## D-014 — ElastiCache fora do escopo (2026-11-20, agente)

Contexto: o README do coordenador lista o ElastiCache entre os recursos do Terraform, mas nenhum dos três serviços usa cache. O enunciado (fonte normativa) não o exige; o mapa trata o item como bônus condicionado a uso real (REQ-BON-04, dúvida Q-22).
Decisão: não provisionar ElastiCache. Justificativa FinOps: recurso sem uso é desperdício. O relatório explica a escolha.
Alternativas: provisionar sem uso (custo sem benefício) ou criar um cache de `GET /ngos` (mudaria o código além do mínimo da D-009).
Status: vigente; reabrir se o tutor responder que é obrigatório.

## D-013 — Tracing entre serviços (2026-11-20, agente)

Contexto: os serviços não chamam uns aos outros e a fila SQS não tem consumidor. A Fase 4 provou tracing com um trace que atravessava 5 serviços; aqui isso não se repete sem mudar o código.
Decisão: serviços independentes, cada um com traces próprios (HTTP → PostgreSQL, SQS ou DynamoDB). O donation-service injeta o contexto W3C (`traceparent`) nas MessageAttributes da mensagem SQS, deixando o elo pronto para um consumidor futuro. Nenhuma chamada nova entre serviços.
Alternativas: volunteer consultar o ngo para validar `ngo_id`; donation validar no ngo (acoplaria o hot path); criar um consumidor da fila (mais um serviço).
Status: vigente; aplicada na C1.

## D-012 — Bootstrap do Terraform e provedor OIDC (2026-11-20, agente)

Contexto: na Fase 4 o bucket de estado, o provedor OIDC do GitHub e o Budget nasceram fora do Terraform. A Fase 5 proíbe infraestrutura clicada (REQ-OBR-03). O bucket da Fase 4 foi removido em 2026-11-12; o provedor OIDC do GitHub foi mantido na conta, segundo o encerramento da Fase 4.
Decisão: raiz `terraform/bootstrap/` que cria o bucket de estado (versionado, cifrado, bloqueio público e policy só TLS) e o Budget (D-008), e importa o provedor OIDC existente com bloco `import`, sem recriá-lo. O estado do bootstrap começa local e é migrado para o próprio bucket logo após o primeiro apply. A existência do provedor é conferida na C2, antes do plano.
Alternativas: recriar o provedor (ação destrutiva fora do código) ou só lê-lo por data source (continuaria fora do código).
Status: vigente; aplicada na C2.

## D-011 — Atribuição e documentos públicos (2026-11-20, agente)

Contexto: o repositório é público. A F4-D-018 definiu documentos públicos focados no projeto, com autoria de agentes e IDs internos no diário. Na Fase 5, o commit `7552369` já usou o trailer `Co-Authored-By`, e o PR #1 o rodapé do Claude Code; o usuário mesclou o PR.
Decisão: manter a F4-D-018 para documentos públicos (README, `docs/`, código): sem nomes de agentes nem IDs internos como D-/P-. O diário (`00_COLAB_IA/`) registra autoria e IDs. Nos commits e PRs, a autoria do agente vai como metadado (trailer e rodapé), como já feito. Memória global do assistente só quando o usuário pedir diretamente.
Alternativas: commits sem trailer (padrão da Fase 4).
Status: vigente; o usuário pode vetar.

## D-010 — Colaboração entre Claude e Codex (2026-11-20, usuário/agente)

Contexto: o usuário pediu "sempre mantenha nosso projeto atualizado para ele [o Codex] poder atuar em qualquer momento caso acabe seus créditos". A Fase 4 não tinha `AGENTS.md`.
Decisão: `AGENTS.md` na raiz (lido automaticamente pelo Codex) e `.claude/CLAUDE.md` (Claude), ambos ponteiros curtos para `00_COLAB_IA/LEIA-PRIMEIRO.md`. Numeração nova (D-001, P-001, F-001). Toda camada termina com LOG e PENDENCIAS atualizados e commit, para que o outro agente retome do Git.
Alternativas: um só arquivo de contexto (um dos dois agentes ficaria sem porta de entrada automática).
Status: vigente.

## D-009 — Alterações no código recebido (2026-11-20, agente)

Contexto: o código do coordenador não tem Dockerfile, testes nem `go.sum`, e usa versões antigas (Go 1.21, Flask 2.2.2). O pedido exige "implemente tudo que foi passado da documentação da fase 5", o que inclui instrumentação (REQ-OBR-13) e testes no pipeline (REQ-OBR-08). O README do coordenador convida a "evoluir a arquitetura, melhorar a observabilidade e implementar boas práticas".
Decisão: alterações mínimas e documentadas: Dockerfile, `go.sum`, testes, instrumentação OpenTelemetry, logs JSON, desligamento gracioso e atualização de dependências quando o build ou o scan exigirem. Rotas, payloads, portas, variáveis de ambiente e regras de negócio não mudam. O código original entra num commit próprio, para que o diff mostre só o que foi alterado.
Alternativas: não mexer no código (inviabiliza APM e testes) ou refatorar livremente (risco sem ganho para a avaliação).
Status: vigente; aplicada na C1.

## D-008 — Orçamento AWS (2026-11-20, usuário)

Contexto: cerca de US$ 126 de crédito; a stack da Fase 4 custava cerca de US$ 0,41/h ligada. O Budget da Fase 4 (US$ 80) foi criado fora do Terraform e continua existindo.
Decisão: resposta do usuário: "US$ 50/mês (Recomendado)". Budget mensal de US$ 50 criado pelo Terraform (raiz bootstrap), filtrado pela tag `Project=SolidaryTech`, com alertas por e-mail a 50%, 80% e 100%. O e-mail fica só num tfvars local ignorado pelo Git. O Budget da Fase 4 não é alterado.
Alternativas: US$ 80/mês, como na Fase 4.
Status: vigente; aplicada na C2.

## D-007 — README do coordenador (2026-11-20, usuário)

Contexto: o README do repositório oficial, copiado pelo usuário para a raiz, é referência de requisitos.
Decisão: resposta do usuário: "Mover para docs (Recomendado)". Cópia byte a byte em `docs/enunciado/README-coordenador.md` (SHA-256 conferido igual ao original) e README do projeto na raiz, com link para o original.
Alternativas: manter o original na raiz e documentar o projeto em `docs/README.md`.
Status: concluída em 2026-11-20.

## D-006 — Fluxo de Git (2026-11-20, usuário)

Contexto: a Fase 4 trabalhou na `dev`, com commits curados, push autorizado e PR para a `main`.
Decisão: resposta do usuário: "Sim, como na Fase 4 (Recomendado)". Trabalho na `dev` com commits curados por camada e push na `origin/dev`; `dev` → PR → `main` com `gh pr merge --merge`, nunca `--delete-branch`. PR e merge na `main` pedem autorização específica. Depois que o robô do CI passar a comitar na `main`, sincronizar a `dev` com a `main` antes de novas mudanças. O PR #1 (guias de estudo) já estava mesclado na `dev` pelo usuário (`4a6ef6b`).
Alternativas: uma branch por camada com PR para a `dev`.
Status: vigente.

## D-005 — Estratégia de DR (2026-11-20, usuário)

Contexto: o enunciado aceita a Opção A (Velero salvando o estado do cluster em bucket externo) ou a Opção B (Terraform modular que levanta um ambiente espelho em outra região com 1 comando). As doações ficam no RDS, fora do cluster: o Velero sozinho não as protege.
Decisão: resposta do usuário: "Opção A — Velero (Recomendado)". Velero via ArgoCD com bucket S3 em us-east-1; RDS com backup automático, PITR e cópia dos backups em us-east-1; DynamoDB com PITR. Demonstração: apagar o namespace e restaurar, cronometrando o RTO. RTO e RPO-alvo propostos na C9 e aprovados pelo usuário (P-007).
Alternativas: Opção B (segundo ambiente inteiro enquanto ligado, cota de vCPU a conferir, EKS leva dezenas de minutos para subir); A + B (bônus REQ-BON-34).
Status: vigente; aplicada na C9.

## D-004 — APM, incidentes e ChatOps (2026-11-20, usuário)

Contexto: a Fase 4 usou New Relic (região US), PagerDuty (trial) e Slack.
Decisão: resposta do usuário: "Vamos reaproveitar tudo menos o pager duty, irei tentar criar outra conta no pager duty para termos mais um trail, de resto, mantenha. Onde precisar de informações do pager duty sinaliza para preenchermos mais para frente." New Relic e Slack da Fase 4 reaproveitados. PagerDuty em conta nova criada pelo usuário; todo campo que depender dele leva o marcador `A PREENCHER (PagerDuty)` e entra na P-002. Chaves só no `.env` local, nunca no chat, no LOG ou em arquivo versionado.
Alternativas: contas novas para tudo.
Status: vigente; confirmar na C8 se o plano do New Relic tem a detecção de anomalias (P-005).

## D-003 — Conta AWS, regiões e ciclo de vida (2026-11-20, usuário)

Contexto: a conta pessoal da Fase 4 (final 6140) está vazia desde 2026-11-12, tem cerca de US$ 126 de crédito e cota de 5 vCPU On-Demand.
Decisão: resposta do usuário: "Conta da Fase 4, liga/desliga (Recomendado)". Mesma conta e região primária us-east-2; região secundária us-east-1 para DR. O ambiente sobe nas janelas de teste e gravação e é destruído depois, sempre com `plan -out` e `apply` do plano salvo. Cada apply ou destroy pede autorização específica do usuário (P-004). `allowed_account_ids` em todos os providers.
Alternativas: outra conta pessoal.
Status: vigente.

## D-002 — Base técnica (2026-11-20, usuário)

Contexto: o usuário pediu "pode se basear no tech challenge 4".
Decisão: o repositório `tech-challenge-04` é referência somente leitura. O que reaproveitar está no [mapeamento](02_TRABALHO/MAPEAMENTO_BASE_FASE4_2026-11-20_v01.md). Versões de ferramentas, charts e imagens são revisadas na data de uso, não copiadas às cegas.
Status: vigente.

## D-001 — Escopo: só obrigatórios (2026-11-20, usuário)

Contexto: o mapa de requisitos tem 47 obrigatórios, 46 bônus e 19 sugestões.
Decisão: pedido do usuário: "trabalhe em cima dele apenas com as itens obrigatórios, quero entregar algo simples, bem feito e que funcione. Caso sobre tempo podemos implementar melhorias no futuro." Bônus e sugestões ficam no backlog do mapa e não entram no plano.
Status: vigente.
