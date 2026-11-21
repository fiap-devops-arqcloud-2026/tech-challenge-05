# Colaboração entre agentes (Claude e Codex)

TL;DR: Retomar pela camada em andamento em [PENDENCIAS](PENDENCIAS_E_PROXIMOS_PASSOS.md) e pelo topo do [LOG](LOG_DE_TRABALHO.md). O plano completo está no [PLANO_DE_ACAO](PLANO_DE_ACAO.md) e as escolhas em [DECISOES](DECISOES.md). Nenhum recurso AWS da Fase 5 existe; apply e destroy só com autorização específica.

Última atualização: 2026-11-20, Claude.

## Projeto em uma frase

Plataforma SolidaryTech (Hackathon da Fase 5 da POSTECH DevOps e Arquitetura Cloud): três microsserviços do coordenador (`ngo-service` em Python, `donation-service` em Go, `volunteer-service` em Python) operados na AWS com Terraform, EKS, GitOps, observabilidade, SRE, FinOps, AIOps e DR, só com os itens obrigatórios do enunciado (D-001).

## Ritual de retomada

1. Descobrir data e hora (`date`); trabalhar em português do Brasil e usar datas ISO (AAAA-MM-DD).
2. Conferir `git status --short` e a branch (`dev`). Se houver mudanças não comitadas de outro agente, ler o topo do LOG antes de tocar nelas.
3. Ler PENDENCIAS (camada em andamento), o topo do LOG e, se preciso, o PLANO_DE_ACAO, as DECISOES e o [DOSSIE](DOSSIE_CONTEXTO.md).
4. Continuar da primeira entrega não concluída. Verificar arquivos já salvos antes de repetir trabalho.
5. Ao concluir cada entrega: marcar em PENDENCIAS, atualizar a matriz do plano e registrar no LOG (entrada nova no topo, sem apagar as antigas, terminando em "Estado p/ próximo agente").
6. Ao fim de cada camada: commit curado na `dev` (D-006) e teste de handoff (outro agente consegue continuar só com AGENTS.md → LEIA-PRIMEIRO → PENDENCIAS → LOG).

IDs: D-### decisões, P-### pendências que dependem de alguém, F-### achados. Herança da Fase 4 com prefixo F4-, da Fase 3 com F3-.

## Regras que valem sempre

### Fontes e escopo

- Cada obrigação precisa de página ou trecho do enunciado (`POSTECH - DCLT - Hackathon - Fase 5.pdf`, na raiz) ou do [mapa de requisitos](../docs/requisitos/README.md). Ambiguidade vira `[INCERTO]`; contradição entre agentes vira `⚠️ CONFLITO` com pedido de esclarecimento ao usuário.
- **Não inventar dados.** Número medido leva data e fonte; meta (SLO, RTO, RPO, orçamento) é decisão do usuário, proposta pelo agente e registrada em DECISOES.
- O enunciado, os PDFs de aula, `docs/enunciado/README-coordenador.md` e o repositório `tech-challenge-04` são somente leitura.
- Procurar na fonte óbvia antes de abrir pendência ou perguntar. Depois de cada decisão, revisar as pendências que ficaram obsoletas.

### Segredos

- Segredo nunca aparece em terminal, chat ou arquivo versionado. Para conferir, mostrar só presença/ausência e resultado de validação, nunca o valor nem o prefixo da chave.
- Chaves de SaaS (New Relic, PagerDuty, Slack) e tokens ficam no `.env` local, ignorado pelo Git (D-004). Valores sensíveis do Terraform entram por `TF_VAR_*` ou tfvars local ignorado.
- O repositório é **público**: tudo o que for commitado fica público, inclusive o histórico. Não citar o ID completo da conta AWS em documentos; usar "final 6140".
- Antes de cada commit, rodar `bash scripts/security-check.sh` e revisar o diff em busca de credenciais, `.env`, chave privada, kubeconfig, tfstate e dados pessoais.

### Git

- Nunca usar `git add .` nem `git add -A`: adicionar arquivo por arquivo, pelo caminho.
- Fluxo: `dev` → PR → `main` com `gh pr merge --merge`. Nunca usar `--delete-branch` (apagaria a `dev`). PR e merge na `main` pedem autorização específica (D-006).
- Commits curados e push na `origin/dev` fazem parte do fluxo aprovado. Mensagens no padrão Conventional Commits, em português.

### AWS e Terraform

- Conta pessoal da Fase 4, us-east-2 primária e us-east-1 secundária (D-003). `allowed_account_ids` em todos os providers.
- Leitura (`describe`, `list`, `get`) pode ser feita para planejar. **Criar, alterar ou destruir recursos só com autorização específica do usuário** a cada janela (P-004).
- Terraform sempre com plano salvo: `terraform plan -out=<camada>.tfplan` e depois `terraform apply <camada>.tfplan`. No destroy, `terraform plan -destroy -out=<camada>-destroy.tfplan`. Nunca apply interativo.
- Regra de Ouro do enunciado: nada de `kubectl apply` manual, nada de recurso clicado no console, nada de serviço sem monitoramento.

### Escrita e código

- Explicação simples antes da técnica. Comentar o código explicando o porquê; em documentos, uma linha de comentário acima de cada comando mostrado.
- Todo documento tem TL;DR e "Última atualização: AAAA-MM-DD, agente". Correção vira retificação datada, sem apagar o histórico.
- Documentos públicos (README, `docs/`, código) não citam agentes nem IDs internos (F4-D-018, mantida na D-011). Autoria fica no LOG e nos metadados do commit.
- Arquivos auxiliares em `02_TRABALHO/` com o padrão `NOME_AAAA-MM-DD_vNN`; versões substituídas vão para `_ARQUIVO_MORTO/` com um DE-PARA.
- Memória global do assistente só quando o usuário pedir diretamente.

### Shell no Windows

- Git Bash: um comando por linha nos guias; `python`/`python3` pode cair no atalho da Microsoft Store, então usar `py -I`. Caminhos do Python no formato `C:/...`.
- PowerShell 5.1: não há `&&` (usar `; if ($?) { ... }`); `curl` é `Invoke-WebRequest` (usar `curl.exe`).

## Evidência em cinco estados

Código existente → verificação local → execução no CI → funcionamento na AWS → evidência de entrega. Um estado não substitui o outro: CI verde não prova Pod no EKS, e `terraform validate` não prova recurso criado. Cada item da matriz do plano diz em qual estado está.
