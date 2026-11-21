# Hackathon Fase 5 (SolidaryTech) — contexto para assistentes

TL;DR: C0 concluída em 2026-11-20; próxima camada C1 (serviços e contêineres), local e sem custo. Nenhum recurso AWS da Fase 5 existe; apply e destroy só com autorização específica do usuário.

Última atualização: 2026-11-20, Claude.

- Ler `00_COLAB_IA/LEIA-PRIMEIRO.md` → `PENDENCIAS_E_PROXIMOS_PASSOS.md` → topo do `LOG_DE_TRABALHO.md` → `PLANO_DE_ACAO.md` e `DECISOES.md` conforme a necessidade. As mesmas regras valem para o Codex, que entra por `AGENTS.md`.
- Escopo só obrigatório (D-001). Conta AWS da Fase 4, us-east-2 + us-east-1 para DR, ambiente liga/desliga (D-003). DR pela Opção A — Velero (D-005). Budget de US$ 50/mês (D-008).
- Repositório **público**; segredos só no `.env` local; nunca `git add .`/`-A`; nunca `--delete-branch`; commits curados e push na `dev`; PR/merge na `main` com autorização (D-006).
- Documentos públicos sem nomes de agentes nem IDs internos (D-011). Memória global somente quando pedida diretamente.
- Encerrar cada tarefa com LOG, PENDENCIAS, matriz do plano e teste de handoff.
