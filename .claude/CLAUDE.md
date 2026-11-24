# Hackathon Fase 5 (SolidaryTech) — contexto para assistentes

TL;DR: C0, C1 e C3 concluídas (CI verde no GitHub); C2 (Terraform) validada e revisada; C4 (GitOps) com os manifestos validados. Na AWS existem o bootstrap e a base (sem NAT), aplicados em 2026-11-24; cluster e k8s não. Próximo: Variables do GitHub e PR para a main, cada um com autorização do usuário.

Última atualização: 2026-11-24, Claude.

- Ler `00_COLAB_IA/LEIA-PRIMEIRO.md` → `PENDENCIAS_E_PROXIMOS_PASSOS.md` (seção "Fase AWS") → topo do `LOG_DE_TRABALHO.md` → `PLANO_DE_ACAO.md` e `DECISOES.md` conforme a necessidade. As mesmas regras valem para o Codex, que entra por `AGENTS.md`.
- Escopo só obrigatório (D-001). Conta AWS da Fase 4, us-east-2 + us-east-1 para DR, ambiente liga/desliga (D-003). DR pela Opção A — Velero (D-005). Budget de US$ 50/mês (D-008).
- Repositório **público**; segredos e dados pessoais só no `.env` e nos tfvars locais; nunca `git add .`/`-A`; nunca `--delete-branch`; commits curados e push na `dev`; PR/merge na `main` e cada apply/destroy com autorização (D-006, P-004).
- Push que mexe em `.github/workflows/` precisa do token do `gh` (escopo `workflow`): ver LEIA-PRIMEIRO, seção Git.
- Crédito ou limite de uso perto do fim: registrar LOG e PENDENCIAS e commitar ANTES de continuar (D-018).
- Documentos públicos sem nomes de agentes nem IDs internos (D-011). Memória global somente quando pedida diretamente.
- Encerrar cada tarefa com LOG, PENDENCIAS, matriz do plano e teste de handoff.
