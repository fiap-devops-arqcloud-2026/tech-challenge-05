# Hackathon Fase 5 — Mapa de requisitos (SolidaryTech)

> 🗺️ **Versão visual e interativa:** [REQUISITOS.html](REQUISITOS.html) — filtros, busca, progresso e matriz de evidências. Gerado em 2026-11-11.

## 1. TL;DR

Fonte normativa: [enunciado do Hackathon](../aulas-fiap/POSTECH%20-%20DCLT%20-%20Hackathon%20-%20Fase%205.pdf) (8 páginas; exigências nas p. 2–7). O desafio é construir, orquestrar, monitorar, otimizar financeiramente e tornar resiliente o novo ecossistema da **SolidaryTech** — `ngo-service`, `donation-service` (Hot Path) e `volunteer-service` — aplicando toda a base das Fases 1 a 4 (Regra de Ouro: sem `kubectl` manual, sem infraestrutura clicada, sem voo cego). A entrega é avaliada em **5 frentes**: Fundação DevOps, SRE, FinOps, ITSM/AIOps e Multicloud/Segurança/DR. Entregáveis: repositório, **vídeo de até 20 min** (pitch executivo + demo) e **relatório PDF** com seções SRE, FinOps, Segurança/DR e ITSM/AIOps. A atividade vale 90% da nota das disciplinas da fase.

Este mapa contém **47 obrigatórios 🔴, 46 bônus 🟢 (sem pontuação extra prometida), 19 sugestões 🔵 e 22 dúvidas ❓**. Tudo está **Pendente**: estudar não comprova implantação.

## 2. Como ler

| Selo | Significado |
|---|---|
| 🔴 Obrigatório | Exigido pelo enunciado. O que não for demonstrado no vídeo ou documentado no relatório sofre dedução direta (p. 6). |
| 🟢 Bônus | Diferencial: excede um “no mínimo”/“pelo menos”, usa a opção não escolhida ou aplica algo do material oficial não cobrado. O PDF não promete pontos extras. |
| 🔵 Sugestão | Recomendação autoral para reduzir risco; não é exigência da FIAP. |
| ❓ Dúvida | Ambiguidade a levar ao tutor; até lá, leitura conservadora marcada com [INCERTO]. |

Na coluna **Onde**: 📁 Repositório · 🎬 Vídeo · 📄 Relatório; ● = exigido explicitamente ali, ◐ = recomendado para cumprir a regra de avaliação.

## 3. Entregáveis e formato

| Entregável | Conteúdo exigido | Fonte |
|---|---|---|
| 📁 Repositório | Terraform completo com tags FinOps; manifestos YAML com requests/limits; pipelines (GitHub Actions/GitLab CI) com DevSecOps | p. 6 |
| 🎬 Vídeo (até 20 min) | Pitch executivo (arquitetura, PCN, estratégias financeiras) + demo: CI/CD e deploy via ArgoCD; Terraform/tags; traces e alertas no APM; Dashboard SRE com SLOs; Backup/DR em ação | p. 6 |
| 📄 Relatório (.PDF) | Nomes, RMs e usernames; links do repositório e do vídeo; seções SRE (SLI, SLO, SLA), FinOps (Forecast + tags), Segurança e DR (PCN com RPO/RTO + estratégia), ITSM/AIOps (ciclo de incidentes) | p. 7 |

## 4. 🔴 Requisitos obrigatórios

### 🧱 Frente 0 — Fundação DevOps

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-01"></a>REQ-OBR-01 | **Regra de Ouro: aplicar as Fases 1–4** — Aplicar toda a base tecnológica das Fases 1, 2, 3 e 4 ao novo ecossistema SolidaryTech (três microsserviços). | p. 2 | ● | ● | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-02"></a>REQ-OBR-02 | **Zero deploy manual via kubectl** — Nenhuma implantação manual com `kubectl`: todo deploy passa por pipeline e GitOps. | p. 2 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-03"></a>REQ-OBR-03 | **Zero infraestrutura “clicada” no console** — Nenhum recurso criado à mão no console da nuvem: toda a infraestrutura nasce do código Terraform. | p. 2 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-04"></a>REQ-OBR-04 | **Zero “voo cego”: monitoramento profundo** — Monitoramento profundo de todo o ecossistema — os três serviços, não apenas o `donation-service`. | p. 2 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-05"></a>REQ-OBR-05 | **Dockerfiles otimizados para os 3 serviços** — Criar Dockerfiles otimizados para `ngo-service` (Python/Flask), `donation-service` (Go) e `volunteer-service` (Python/Flask). Ver Q-19. | p. 3 | ● | ◐ |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-obr-06"></a>REQ-OBR-06 | **Kubernetes gerenciado (EKS, AKS ou GKE)** — Implantar os três serviços em Kubernetes gerenciado: EKS, AKS ou GKE. Ver Q-17. | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-obr-07"></a>REQ-OBR-07 | **Terraform provisiona todo o ambiente** — Provisionar via Terraform todo o ambiente: cluster, bancos de dados (PostgreSQL e DynamoDB), mensageria (SQS) e rede. | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-08"></a>REQ-OBR-08 | **CI/CD automatizado com testes** — Pipelines de CI/CD automatizados (ex.: GitHub Actions) que executem testes. Ver Q-20. | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-09"></a>REQ-OBR-09 | **Scans SAST/SCA no pipeline** — Incluir scans de segurança SAST e SCA no pipeline (ferramentas como Trivy ou Sonar). | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-10"></a>REQ-OBR-10 | **Build da imagem no pipeline** — Construir as imagens de contêiner dentro do pipeline. | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-11"></a>REQ-OBR-11 | **GitOps com ArgoCD ou FluxCD** — Entrega contínua configurada via GitOps, com ArgoCD ou FluxCD. Ver Q-04. | p. 3 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-12"></a>REQ-OBR-12 | **Stack de observabilidade rodando** — Stack de observabilidade completa em execução: Prometheus, Grafana, Loki e/ou OpenTelemetry. Ver Q-03. | p. 4 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-13"></a>REQ-OBR-13 | **APM com Distributed Tracing** — Instrumentar o código no APM (Datadog ou New Relic) com Distributed Tracing. | p. 4 | ● | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-14"></a>REQ-OBR-14 | **Automação de resposta a incidentes** — Manter no novo ecossistema as automações de resposta herdadas da Fase 4: alerta → incidente/notificação → ação automática. ⚠️ [INCERTO] inferido: Regra de Ouro (p. 2), item de MTTR que cita “automações de resposta a incidentes” (p. 4) e “alertas configurados” na demo (p. 6). Ver Q-09. | p. 2, 4, 6 | ◐ | ● | ● | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🎯 Frente 1 — SRE

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-15"></a>REQ-OBR-15 | **≥ 2 SLIs do donation-service** — Definir e documentar, para o `donation-service`, no mínimo dois SLIs baseados nas Golden Metrics (ex.: latência e taxa de erros). | p. 4 |  | ● | ● | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-16"></a>REQ-OBR-16 | **Um SLO para cada SLI** — Estabelecer um SLO para cada SLI definido (ex.: 99,9% de sucesso). | p. 4 |  | ● | ● | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-17"></a>REQ-OBR-17 | **Dashboard SRE: SLOs e Error Budget** — Criar um painel específico no Grafana ou no APM focado exclusivamente nos SLOs e no consumo do Error Budget. Ver Q-18. | p. 4 | ◐ | ● | ◐ | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-18"></a>REQ-OBR-18 | **Relatório: como o MTTR é reduzido** — Evidenciar no relatório como a stack de observabilidade e as automações de resposta a incidentes reduzem ativamente o MTTR. | p. 4 |  | ◐ | ● | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 💰 Frente 2 — FinOps

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-19"></a>REQ-OBR-19 | **Política de tags no Terraform** — Implementar política de tags rigorosa no código Terraform: todos os recursos com `Project=SolidaryTech`, `Environment=Production` e `CostCenter=NGO-Core`. Ver Q-10. | p. 4 | ● | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-20"></a>REQ-OBR-20 | **Rightsizing de requests/limits** — Analisar as métricas de CPU/memória do Kubernetes e ajustar `requests` e `limits` dos Pods nos manifestos YAML, via GitOps. | p. 4 | ● | ◐ | ◐ | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-21"></a>REQ-OBR-21 | **Forecast de custos mensais** — Criar uma projeção (Forecast) dos custos mensais da arquitetura. Ver Q-16. | p. 4 |  | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-22"></a>REQ-OBR-22 | **≥ 1 recomendação de otimização nativa** — Indicar pelo menos uma recomendação prática de otimização nativa de nuvem. | p. 4 |  | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |

### 🤖 Frente 3 — ITSM e AIOps

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-23"></a>REQ-OBR-23 | **IA do APM detectando anomalias** — Ativar as funcionalidades de IA do APM (ex.: Watchdog no Datadog ou Applied Intelligence no New Relic) para detectar anomalias comportamentais automaticamente. Ver Q-11. | p. 5 |  | ◐ | ◐ | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-24"></a>REQ-OBR-24 | **Ciclo de vida do incidente desenhado** — Desenhar o fluxo de vida de um incidente da SolidaryTech: da detecção via AIOps/alerta até o PostMortem e a comunicação aos stakeholders. Ver Q-12. | p. 5 |  | ◐ | ● | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🛟 Frente 4 — Multicloud, Segurança e DR

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-25"></a>REQ-OBR-25 | **Documento executivo de PCN** — Escrever um documento executivo de Plano de Continuidade de Negócios (PCN). | p. 5 |  | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-26"></a>REQ-OBR-26 | **RTO e RPO dos dados de doação** — Definir os valores críticos de RTO (Recovery Time Objective) e RPO (Recovery Point Objective) para os dados das doações. | p. 5 |  | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-27"></a>REQ-OBR-27 | **Estratégia de DR implementada** — Implementar e evidenciar backup/DR: **Opção A** — Velero salvando o estado do cluster (manifestos e volumes) em bucket externo; **ou Opção B** — Terraform modular que levanta um ambiente espelho (Warm Standby) em outra região com 1 comando. Ver Q-13, Q-21. | p. 5 | ◐ | ● | ● | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |

### 📦 Entregáveis

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-28"></a>REQ-OBR-28 | **Regra de avaliação: mostrar funcionando** — Evidenciar o funcionamento de todas as métricas, configurações e requisitos. O que não for demonstrado no vídeo ou documentado no relatório sofre dedução direta; não basta configurar. | p. 6 |  | ● | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-29"></a>REQ-OBR-29 | **Repositório: Terraform com tags FinOps** — Entregar no repositório o código IaC completo (Terraform) com as tags FinOps. | p. 6 | ● |  |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-30"></a>REQ-OBR-30 | **Repositório: YAML com requests/limits** — Entregar os manifestos YAML configurados com `requests`/`limits` (Rightsizing). | p. 6 | ● |  |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-31"></a>REQ-OBR-31 | **Repositório: pipelines com DevSecOps** — Entregar os arquivos de pipeline (GitHub Actions/GitLab CI) contemplando DevSecOps. | p. 6 | ● |  |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-32"></a>REQ-OBR-32 | **Vídeo de até 20 minutos** — Vídeo de demonstração com duração de até 20 minutos. Ver Q-01. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-33"></a>REQ-OBR-33 | **Pitch executivo para a diretoria** — Pitch executivo: apresentar arquitetura, PCN e estratégias financeiras como se vendesse a viabilidade do projeto à diretoria da ONG. Ver Q-01. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-34"></a>REQ-OBR-34 | **Demo: CI/CD rodando + deploy via ArgoCD** — Mostrar os pipelines de CI/CD rodando e o deploy no cluster via ArgoCD. Ver Q-04. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-35"></a>REQ-OBR-35 | **Demo: Terraform rodando / recursos com tags** — Exibir o Terraform rodando (ou evidenciar a criação de recursos baseada em tags). | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-36"></a>REQ-OBR-36 | **Demo: traces no APM e alertas** — Mostrar a rastreabilidade no APM (traces) e os alertas configurados. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-obr-37"></a>REQ-OBR-37 | **Demo: Dashboard SRE com SLOs calculados** — Mostrar o Dashboard SRE com as Golden Metrics e os SLOs calculados. Ver Q-18. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-38"></a>REQ-OBR-38 | **Demo: Backup/DR em ação** — Demonstrar o sistema de Backup/DR em ação (ex.: Velero, ou módulos Terraform prontos para a região secundária). Ver Q-13. | p. 6 |  | ● |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-obr-39"></a>REQ-OBR-39 | **Relatório em PDF** — Entregar o relatório de entrega em formato PDF. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-40"></a>REQ-OBR-40 | **Relatório: nomes, RMs e usernames** — Identificar no relatório os nomes, RMs e usernames dos integrantes. Ver Q-15. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-41"></a>REQ-OBR-41 | **Relatório: links do repositório e do vídeo** — Incluir no relatório os links do repositório de código e do vídeo. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-42"></a>REQ-OBR-42 | **Seção SRE: SLI, SLO e SLA formais** — Seção SRE com a definição formal de SLI, SLO **e SLA** do serviço de doações. Ver Q-14. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-obr-43"></a>REQ-OBR-43 | **Seção FinOps: Forecast + evidência de tags** — Seção FinOps com a análise de custos mensais (Forecast) e evidências das tags aplicadas. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-obr-44"></a>REQ-OBR-44 | **Seção Segurança e DR: PCN + estratégia** — Seção Segurança e DR com o documento de PCN (com RPO e RTO) e a explicação da estratégia de Disaster Recovery. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-obr-45"></a>REQ-OBR-45 | **Seção ITSM/AIOps: ciclo de incidentes** — Seção ITSM/AIOps com o desenho do ciclo de vida de incidentes. Ver Q-12. | p. 7 |  |  | ● | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### ⏱️ Transversal

| ID | Requisito | Evidência | 📁 | 🎬 | 📄 | Guias |
|---|---|---|:-:|:-:|:-:|---|
| <a id="req-obr-46"></a>REQ-OBR-46 | **Desenvolvimento em grupo** — Desenvolver o Hackathon em grupo (leitura conservadora). ⚠️ [INCERTO] o PDF diz “em princípio”. Ver Q-05. | p. 2 |  |  |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="req-obr-47"></a>REQ-OBR-47 | **Entrega dentro do prazo** — Submeter código, vídeo e relatório no prazo do Hackathon (2 meses corridos); a atividade vale 90% da nota das disciplinas da fase. ⚠️ [INCERTO] data, hora e canal não constam no PDF. Ver Q-06, Q-07. | p. 2 |  |  |  | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |

## 5. 🟢 Bônus — diferenciais (sem pontuação prometida)

### 🧱 Frente 0 — Fundação DevOps

| ID | Diferencial | De onde vem | Por que vale | Guias |
|---|---|---|---|---|
| <a id="req-bon-01"></a>REQ-BON-01 | **Health checks nas probes e no pipeline** — Usar o `/health` dos três serviços em probes de liveness/readiness e numa verificação de saúde pós-deploy no pipeline. | Material oficial, não exigido no enunciado: README do repositório-fonte (Health Checks, Auto Healing); SRE Aula 1, p. 4 | Evita tráfego para Pods não prontos e barra deploys quebrados antes de afetar doadores. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-02"></a>REQ-BON-02 | **Autoscaling para picos imprevisíveis** — HPA nos Deployments e autoscaling de nós para absorver picos de acesso. | Decorre do cenário narrado: Enunciado p. 3 (picos de acesso imprevisíveis após exposição na TV) | Conecta o cenário narrado à arquitetura e conversa com rightsizing e Forecast. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-03"></a>REQ-BON-03 | **DynamoDB: Query em GSI no lugar de Scan** — Trocar o `Scan` com filtro por `ngo_id` por `Query` num índice secundário global (GSI) criado no Terraform. | Material oficial, não exigido no enunciado: Comentário “Nota para avaliação dos alunos” em `volunteer-service/app.py` | O próprio código-fonte sinaliza o ponto para avaliação; reduz latência e consumo de leitura (custo). | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-04"></a>REQ-BON-04 | **ElastiCache — só com uso real** — Provisionar ElastiCache apenas se algum serviço passar a usá-lo (ex.: cache de `GET /ngos`); hoje nenhum serviço usa cache. | Material oficial, não exigido no enunciado: README do repositório-fonte (lista Amazon ElastiCache no Terraform) | Mostra critério: recurso sem uso é desperdício — exatamente o que FinOps combate. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-05"></a>REQ-BON-05 | **Detecção de drift da infraestrutura** — Rodar `terraform plan` agendado no CI (ou ferramenta de drift) e alertar quando algo mudar fora do código. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 2, p. 6 e 12 (Configuration Drift, driftctl) | Prova continuamente a regra “sem infraestrutura clicada”. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-06"></a>REQ-BON-06 | **Scan de IaC e misconfiguração no pipeline** — Além de SAST/SCA, escanear Terraform e manifestos (ex.: `trivy config`, Checkov) antes do apply. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 3, p. 12 (CSPM e segurança de pipeline) | Pega bucket público, porta aberta e Pod privilegiado antes de existirem. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-07"></a>REQ-BON-07 | **Tail-based sampling no Collector** — Guardar todos os traces com erro ou latência alta e amostrar o restante. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 7, p. 5 (tail-based sampling) | Mantém a evidência dos incidentes e reduz volume e custo de telemetria. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-08"></a>REQ-BON-08 | **Produção sem atalhos (RBAC + aprovação)** — Pessoas só com leitura no cluster e na conta de produção; mudanças apenas por pipeline e ArgoCD, com aprovação registrada para promover. | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 7, p. 11–12 (segregação de ambientes e aprovação formal) | Transforma “sem deploy manual” e “sem console” de promessa em controle técnico. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-09"></a>REQ-BON-09 | **Cadeia de suprimentos: tag imutável, assinatura e SBOM** — Imagens identificadas pelo commit (nunca `latest`), assinadas (ex.: cosign) e acompanhadas de SBOM. | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 5, p. 13 (tags explícitas); Aula 7, p. 15 (assinatura de artefatos) | Garante que o que roda em produção é exatamente o que passou pelos scans. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-10"></a>REQ-BON-10 | **Métricas DORA do pipeline** — Medir frequência de deploy, lead time, taxa de falha de mudança e tempo de recuperação. | Material oficial, não exigido no enunciado: SRE, Aula 1, p. 5 e 7 (DORA); ITSM e AIOps, Aula 7, p. 15 (métricas compartilhadas) | Mostra a saúde da entrega ao lado da saúde do serviço. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🎯 Frente 1 — SRE

| ID | Diferencial | De onde vem | Por que vale | Guias |
|---|---|---|---|---|
| <a id="req-bon-11"></a>REQ-BON-11 | **Mais de dois SLIs no donation-service** — Acrescentar SLIs como publicação bem-sucedida do evento no SQS ou saturação do pool de conexões do banco. | Além do mínimo do PDF: Enunciado p. 4 (“no mínimo, dois SLIs”) | Cobre pontos cegos do Hot Path que o status HTTP não revela. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-12"></a>REQ-BON-12 | **SLOs para os outros serviços ou SLO composto** — Definir SLOs também para `ngo-service` e `volunteer-service`, ou um SLO composto da jornada de doação. | Além do mínimo do PDF: Enunciado p. 4 (exige só o donation-service); SRE Aula 2, p. 7–8 (SLO composto) | Aproxima o SLO da experiência real do doador e da ONG. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-13"></a>REQ-BON-13 | **Alertas por burn rate do Error Budget** — Alertar pela velocidade de consumo do error budget (janela curta e longa), e não por limiares arbitrários. | Material oficial, não exigido no enunciado: SRE Aula 2, p. 9; SRE Aula 3, p. 8 | Gera alertas com impacto real no usuário e menos ruído. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-14"></a>REQ-BON-14 | **Gate de Error Budget no pipeline** — Bloquear deploys no CI/CD quando o error budget estiver esgotado (política de congelamento). | Material oficial, não exigido no enunciado: SRE Aula 2, p. 4 (Hands On) e p. 9 (congelamento de deploys) | Transforma a política de SRE em automação auditável. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-15"></a>REQ-BON-15 | **Runbooks versionados (Runbook-as-Code)** — Runbooks em Markdown no repositório, ligados a cada alerta, com diagnóstico, mitigação e critério de validação. | Material oficial, não exigido no enunciado: SRE Aula 5, p. 4, 6 e 13 (Runbook-as-Code) | Reduz o MTTR e dá material concreto para a seção de MTTR do relatório. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-16"></a>REQ-BON-16 | **Post-mortem blameless de um incidente simulado** — Escrever um post-mortem real (linha do tempo, causa raiz, ações com dono e prazo) do incidente provocado na demo. | Material oficial, não exigido no enunciado: SRE Aula 5, p. 6–8; Enunciado p. 5 (o fluxo termina no PostMortem) | Prova o fim do ciclo de incidente que o enunciado pede apenas desenhado. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-17"></a>REQ-BON-17 | **Game Day / Chaos Engineering** — Rodar um experimento controlado (ex.: Chaos Mesh ou Litmus) para medir MTTR e validar RTO na prática. | Material oficial, não exigido no enunciado: SRE Aula 4, p. 9 e 11 (Chaos Engineering, Game Days) | Mede o que o PCN promete, em vez de apenas declarar. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-18"></a>REQ-BON-18 | **Desligamento gracioso no donation-service** — Tratar SIGTERM e encerrar o servidor HTTP sem cortar requisições em andamento (o código atual não trata). | Material oficial, não exigido no enunciado: FinOps, Aula 3, p. 7 (12-Factor: descartabilidade) | Rollouts, scale-in e instâncias Spot deixam de derrubar doações em curso. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-19"></a>REQ-BON-19 | **Entrega progressiva com rollback automático** — Canary (ou blue-green) do `donation-service` guiado por taxa de erro e latência, com rollback automático (ex.: Argo Rollouts). | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 1, p. 4; Aula 5, p. 10–11; Aula 7, p. 9–10; Aula 8, p. 10 | Uma versão ruim afeta poucos doadores e volta sozinha — protege o SLO e encurta o MTTR. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 💰 Frente 2 — FinOps

| ID | Diferencial | De onde vem | Por que vale | Guias |
|---|---|---|---|---|
| <a id="req-bon-20"></a>REQ-BON-20 | **Mais de uma recomendação de otimização** — Apresentar um conjunto priorizado de recomendações (ex.: Spot, Savings Plans, instâncias Graviton, desligar ambientes ociosos), com economia estimada. | Além do mínimo do PDF: Enunciado p. 4 (“pelo menos uma recomendação”) | Mostra maturidade FinOps e enriquece o pitch financeiro. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-21"></a>REQ-BON-21 | **Implementar a recomendação, não só indicar** — Aplicar de fato uma otimização (ex.: node group Spot para cargas tolerantes a interrupção) e medir o efeito. | Além do mínimo do PDF: Enunciado p. 4 (pede “indicar”) | Transforma recomendação em economia comprovada. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-22"></a>REQ-BON-22 | **Tags adicionais de alocação** — Além das três obrigatórias, tags como `Owner`, `Service`, `ManagedBy=Terraform` e `DataClassification`. | Além do mínimo do PDF: Enunciado p. 4 (tags obrigatórias “como” …) | Permite ratear custo por serviço e por dono, e marcar onde há dado pessoal. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-23"></a>REQ-BON-23 | **Budgets, alertas e anomalias de custo** — Criar orçamentos com alerta e detecção de anomalias de custo (ex.: AWS Budgets e Cost Anomaly Detection) via Terraform. | Material oficial, não exigido no enunciado: README do repositório-fonte (Budgets e alertas financeiros); FinOps, Aula 4, p. 6 e Aula 5, p. 5 (anomalias) | Fecha o ciclo FinOps: prever, acompanhar e ser avisado antes do estouro. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-24"></a>REQ-BON-24 | **FinOps Assessment da SolidaryTech** — Autoavaliar 3–4 capacidades (ex.: alocação, previsão, otimização de workloads, custo unitário) nas cinco lentes, de 0 a 4, e propor um roadmap. | Material oficial, não exigido no enunciado: FinOps, Aula 6 (FinOps Assessment) | Dá ao pitch um “onde estamos e para onde vamos” com método reconhecido. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-25"></a>REQ-BON-25 | **Custo por serviço no cluster (Kubecost/OpenCost)** — Medir custo por namespace/serviço no Kubernetes com Kubecost ou OpenCost. | Material oficial, não exigido no enunciado: Welcome da Fase 5, p. 2–3 (Kubecost e AWS Cost Explorer) | Dá base objetiva ao rightsizing e ao rateio do Forecast. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-26"></a>REQ-BON-26 | **Unit economics: custo por doação** — Calcular o custo de infraestrutura por doação processada (e por R$ doado) e acompanhar a tendência no Forecast e no pitch. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 8, p. 7–8 (Unit Economics); Aula 2, p. 13 | Mostra à diretoria que o gasto cresce menos que o impacto social. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-27"></a>REQ-BON-27 | **Custo estimado no Pull Request** — Exibir o impacto de custo de cada mudança de Terraform no PR (ex.: Infracost). | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 2, p. 13; Aula 8, p. 10 (Shift-Left FinOps) | Leva FinOps para o momento da decisão de engenharia. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="req-bon-28"></a>REQ-BON-28 | **Policy-as-code para tags e guardrails** — Barrar automaticamente recurso sem as tags obrigatórias, imagem fora do registro confiável e exposição pública indevida (ex.: OPA/Conftest, Kyverno). | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 2, p. 11 (OPA); Aula 8, p. 5 (governança por políticas) | Torna a política de tags “rigorosa” verificável, não só declarada. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🤖 Frente 3 — ITSM e AIOps

| ID | Diferencial | De onde vem | Por que vale | Guias |
|---|---|---|---|---|
| <a id="req-bon-29"></a>REQ-BON-29 | **Fluxo ITSM implementado numa ferramenta** — Operar o fluxo de incidente numa ferramenta real (ex.: PagerDuty ou Jira Service Management), com estados, prioridades e responsáveis. | Além do mínimo do PDF: Enunciado p. 5 (pede “desenhar” o fluxo) | Mostra o desenho funcionando, não só no papel. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-30"></a>REQ-BON-30 | **Comunicação automatizada aos stakeholders** — Mensagens padronizadas e automáticas para diretoria e ONGs (ex.: canal de status, página de status). | Além do mínimo do PDF: Enunciado p. 5 (comunicação aos stakeholders) | Materializa a etapa de comunicação que o fluxo exige. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-31"></a>REQ-BON-31 | **Correlação e deduplicação de alertas** — Agrupar alertas da mesma causa num único incidente, com prioridade por impacto no negócio. | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 1, p. 5 (alert fatigue); Aula 8, p. 9–10 (agrupamento); Multicloud e Segurança, Aula 7, p. 10 | Combate a fadiga de alertas — um incidente por causa, não cinquenta notificações. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-32"></a>REQ-BON-32 | **Detector de anomalia complementar** — Uma regra estatística própria (ex.: 3 sigmas sobre métricas do Prometheus) que aciona remediação, ao lado da IA do APM. | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 8, p. 4 (Hands On: regra dos 3 sigmas) | Mostra domínio do mecanismo, não só do botão da ferramenta. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-33"></a>REQ-BON-33 | **Copiloto de incidentes com ferramentas MCP** — Agente que consulta métricas, abre o incidente e posta no canal via ferramentas MCP, com permissões mínimas e auditoria. | Material oficial, não exigido no enunciado: ITSM e AIOps, Aula 6 (MCP); Aula 1, p. 14 (copiloto de plantão da Uber) | Diferencial alto (e trabalhoso) que conecta AIOps à gestão de incidentes. | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🛟 Frente 4 — Multicloud, Segurança e DR

| ID | Diferencial | De onde vem | Por que vale | Guias |
|---|---|---|---|---|
| <a id="req-bon-34"></a>REQ-BON-34 | **As duas estratégias de DR (A + B)** — Implementar Velero (Opção A) e também Warm Standby via Terraform (Opção B). | Alternativa/opção do PDF: Enunciado p. 5 (Opção A ou Opção B) | Combina proteção de estado do cluster com capacidade de subir a infraestrutura em outra região. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-35"></a>REQ-BON-35 | **Backup multicloud de verdade** — Enviar os backups para um bucket em outro provedor de nuvem, e não só para outra região do mesmo provedor. | Alternativa/opção do PDF: Enunciado p. 5 (Opção A — Multicloud/Cross-Region Backup) | Protege contra falha do provedor inteiro — o “se a nuvem cair” do enunciado. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-36"></a>REQ-BON-36 | **Restore/failover real com RTO e RPO medidos** — Executar um restore (ou failover) completo e comparar o RTO/RPO atingidos com os objetivos do PCN. | Além do mínimo do PDF: Enunciado p. 6 (Backup/DR “em ação”); SRE Aula 4, p. 9 e 11 | Converte números do PCN em fatos medidos. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="req-bon-37"></a>REQ-BON-37 | **Backups imutáveis e isolados** — Bucket de backup com bloqueio de objetos (WORM) e, se possível, em conta separada da produção. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 5, p. 17 (imutabilidade e air-gap lógico) | Ransomware procura e apaga backups; imutabilidade e isolamento preservam a última cópia boa. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-38"></a>REQ-BON-38 | **DynamoDB Global Tables no volunteer-service** — Replicar a tabela de voluntários para a região secundária com Global Tables. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 5, p. 12 (bancos globais multi-master) | Dados de voluntários ficam prontos na região de DR sem restore. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-39"></a>REQ-BON-39 | **Failover de tráfego por DNS ou anycast** — Health check e troca automática de destino (ex.: DNS com TTL baixo) para a região secundária. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 5, p. 15 (DNS, TTL e anycast) | Sem redirecionar o tráfego, a região de DR fica pronta mas sem usuários. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-40"></a>REQ-BON-40 | **Identidade de workload com menor privilégio** — IRSA/EKS Pod Identity: o `donation-service` só publica na fila e o `volunteer-service` só acessa a sua tabela — sem chaves estáticas. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 3, p. 7–12 (Zero Trust, CIEM) | Aplica “nunca confie, sempre verifique” ao acesso dos serviços à nuvem. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-41"></a>REQ-BON-41 | **CI autenticando por OIDC, sem chaves** — GitHub Actions assumindo um papel na nuvem via OIDC, sem access keys guardadas em segredos. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 4, p. 12–13 (federação OIDC); Aula 2, p. 9–10 (GitOps pull) | Remove a credencial mais visada do pipeline. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-42"></a>REQ-BON-42 | **Segredos fora do Git** — `DATABASE_URL` e afins num cofre (ex.: Secrets Manager + External Secrets, ou Sealed Secrets), nunca em texto puro no repositório. | Decorre do cenário narrado: Código-fonte (`DATABASE_URL` com senha) + Regra de Ouro (GitOps, sem console) | GitOps exige tudo no Git — menos o segredo em claro. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="req-bon-43"></a>REQ-BON-43 | **Criptografia com chaves gerenciadas pelo cliente** — Chaves KMS próprias (com rotação) para RDS, DynamoDB, S3 e volumes, e TLS em trânsito. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 4, p. 7–12 (PMEK, BYOK, HYOK) | Dados de doadores e voluntários são pessoais; o controle da chave é parte da resposta à LGPD. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-44"></a>REQ-BON-44 | **PII fora da telemetria e dos ambientes de teste** — Remover nome de doador e e-mails de logs e traces no Collector e mascarar dados fora de produção. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 4, p. 13–14 (DLP e mascaramento); Aula 7, p. 6 (Redaction) | Telemetria vai para SaaS de APM; vazar PII por log é incidente de privacidade. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-45"></a>REQ-BON-45 | **Zero Trust dentro do cluster** — NetworkPolicies negando por padrão, só os fluxos necessários liberados, e banco sem endpoint público. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 3, p. 8 (PEP perto do recurso); Aula 6, p. 9–13 (PrivateLink) | Reduz movimento lateral se um Pod for comprometido. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="req-bon-46"></a>REQ-BON-46 | **Postura do Kubernetes endurecida** — Contêineres não root, sem privilégios e com sistema de arquivos somente leitura; Pod Security Admission ou Kyverno aplicando a regra. | Material oficial, não exigido no enunciado: Multicloud e Segurança, Aula 3, p. 12 (KSPM) | Combina com Dockerfiles otimizados e reduz o impacto de uma vulnerabilidade. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |

## 6. 🔵 Sugestões — não são exigências FIAP

### 🧱 Frente 0 — Fundação DevOps

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-01"></a>SUG-01 | **Reaproveitar a base da Fase 4** — Partir dos módulos Terraform, do repositório GitOps, do Collector com spanmetrics, das regras de alerta e da automação PagerDuty/Slack/Actions da Fase 4, adaptando aos três novos serviços. | Atende a Regra de Ouro com menos risco e libera tempo para as frentes novas. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="sug-02"></a>SUG-02 | **Terraform pelo pipeline, não pelo laptop** — `plan` no Pull Request e `apply` pelo pipeline após aprovação. | Arquivos Terraform aplicados à mão viram o anti-padrão “IaC cosmético” (ITSM e AIOps, Aula 7, p. 14). | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="sug-03"></a>SUG-03 | **Schema do banco sem passo manual** — Aplicar os `init.sql` por Job, initContainer ou ferramenta de migração no fluxo GitOps — o README sugere rodá-los à mão. | Executar SQL manualmente é operação fora do código, contra o espírito da Regra de Ouro. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |

### 🎯 Frente 1 — SRE

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-04"></a>SUG-04 | **SLIs limpos: sem /health, com recording rules** — Excluir `/health` e probes do cálculo dos SLIs, pré-calcular com recording rules e conferir se a retenção do Prometheus cobre a janela do SLO. | Probes inflam a taxa de sucesso; retenção curta impede calcular 30 dias. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="sug-05"></a>SUG-05 | **Medir a publicação assíncrona no SQS** — Criar métrica de falhas de envio ao SQS e propagar o contexto de trace no evento, porque o erro da goroutine não altera o status HTTP. | O `donation-service` responde 201 mesmo se o evento não for publicado. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) |
| <a id="sug-06"></a>SUG-06 | **Tráfego sintético contínuo** — Gerar carga contínua e controlada (ex.: k6, Locust ou hey) contra os três serviços durante os testes e a gravação. | Sem tráfego não há SLI, rightsizing com base real, nem padrão para o AIOps aprender. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="sug-07"></a>SUG-07 | **Carimbos de tempo de cada incidente** — Registrar os horários de falha, detecção, reconhecimento, mitigação e recuperação de cada incidente simulado — antes e depois da automação. | É a matéria-prima para provar a redução do MTTR com dados; sem linha de base não há ganho a mostrar. | [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 💰 Frente 2 — FinOps

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-08"></a>SUG-08 | **Tags via default_tags do provider** — Aplicar as tags obrigatórias por `default_tags` no provider AWS (ou `locals` comuns) e listar recursos sem tag antes da entrega. | “Todos os recursos” é fácil de violar quando cada módulo define tags à mão. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="sug-09"></a>SUG-09 | **Tags também no que o cluster cria** — Load balancers, volumes de PVC e instâncias dos node groups não herdam as `default_tags`: configure tags no launch template e nos controladores, e labels de custo nos objetos Kubernetes. | “Todos os recursos” inclui o que o Kubernetes cria sozinho. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="sug-10"></a>SUG-10 | **Forecast em dois tempos e três cenários** — Estimar de baixo para cima (calculadora de preços por componente) e validar de cima para baixo com custos reais por tag, em cenários normal, pico de campanha e com DR. | Com poucas semanas de histórico, a previsão automática é frágil; a diretoria decide por cenários. | [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |
| <a id="sug-11"></a>SUG-11 | **Proteger a conta do próprio grupo** — Orçamento com alerta na conta usada no Hackathon e ambiente destruído e recriado pelo Terraform fora das sessões de trabalho. | São 2 meses de nuvem: a fatura chega antes da nota. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |

### 🤖 Frente 3 — ITSM e AIOps

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-12"></a>SUG-12 | **Ligar a IA do APM cedo** — Ativar a detecção de anomalias semanas antes da gravação, com tráfego estável, e só então provocar uma anomalia controlada. | Detecção de anomalia precisa aprender o “normal”: sem dados bons, não há sinal (ITSM e AIOps, Aula 1, p. 9). | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="sug-13"></a>SUG-13 | **Matriz de autonomia da automação** — Documentar o que a automação faz sozinha (reiniciar Pod, escalar), o que exige aprovação (failover de região) e onde fica o log das ações. | É a governança que as aulas pedem para qualquer remediação automática (ITSM e AIOps, Aula 1, p. 11; Aula 8, p. 14). | [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |

### 🛟 Frente 4 — Multicloud, Segurança e DR

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-14"></a>SUG-14 | **RPO coerente com onde o dado mora** — Garantir que a estratégia de DR cubra o banco das doações onde ele realmente está: o Velero salva o cluster (manifestos e volumes), não um PostgreSQL gerenciado fora dele. | Sem isso, o RPO declarado no PCN não se sustenta. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="sug-15"></a>SUG-15 | **Checklist da região secundária** — Listar o que precisa existir lá: imagens replicadas, segredos, fila SQS, tabela DynamoDB, cópia do banco, estado do Terraform acessível fora da região primária e o cluster registrado no ArgoCD. | Dependências ocultas são a causa clássica de DR que falha no dia (Multicloud e Segurança, Aula 5, p. 20). | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |
| <a id="sug-16"></a>SUG-16 | **Justificar regiões à luz da LGPD** — Explicar no PCN por que as regiões primária e de DR foram escolhidas, considerando residência e transferência internacional de dados de doadores e voluntários. | Região é decisão de custo, latência e conformidade ao mesmo tempo. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) |

### 📦 Entregáveis

| ID | Sugestão | Por que | Guias |
|---|---|---|---|
| <a id="sug-17"></a>SUG-17 | **Matriz de evidências e ensaio cronometrado** — Montar a matriz requisito → evidência (repositório, vídeo, relatório) e ensaiar a demo com cronômetro antes de gravar. | A regra de avaliação pune o que não aparece no vídeo ou no relatório. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html), [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html), [04 ITSM e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) |
| <a id="sug-18"></a>SUG-18 | **Roteiro de vídeo em blocos por frente** — Roteirizar o vídeo como um pitch de 15–20 minutos com a demo embutida, marcando o tempo de cada frente. | Resolve na prática a ambiguidade de duração enquanto a dúvida não é esclarecida. | [00 Welcome](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) |
| <a id="sug-19"></a>SUG-19 | **Falar a língua da diretoria** — Traduzir SLO, error budget, RTO/RPO e Forecast em reais e minutos no pitch. | O enunciado pede vender a viabilidade a uma diretoria de ONG, não a engenheiros. | [01 Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html), [02 SRE](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html), [03 FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) |

## 7. Checklist final de entrega

Os checkboxes medem a implementação e a entrega, não a produção dos guias.

**🧱 Fundação DevOps**

- [ ] **REQ-OBR-01** — Regra de Ouro: aplicar as Fases 1–4
- [ ] **REQ-OBR-02** — Zero deploy manual via kubectl
- [ ] **REQ-OBR-03** — Zero infraestrutura “clicada” no console
- [ ] **REQ-OBR-04** — Zero “voo cego”: monitoramento profundo
- [ ] **REQ-OBR-05** — Dockerfiles otimizados para os 3 serviços
- [ ] **REQ-OBR-06** — Kubernetes gerenciado (EKS, AKS ou GKE)
- [ ] **REQ-OBR-07** — Terraform provisiona todo o ambiente
- [ ] **REQ-OBR-08** — CI/CD automatizado com testes
- [ ] **REQ-OBR-09** — Scans SAST/SCA no pipeline
- [ ] **REQ-OBR-10** — Build da imagem no pipeline
- [ ] **REQ-OBR-11** — GitOps com ArgoCD ou FluxCD
- [ ] **REQ-OBR-12** — Stack de observabilidade rodando
- [ ] **REQ-OBR-13** — APM com Distributed Tracing
- [ ] **REQ-OBR-14** — Automação de resposta a incidentes

**🎯 SRE**

- [ ] **REQ-OBR-15** — ≥ 2 SLIs do donation-service
- [ ] **REQ-OBR-16** — Um SLO para cada SLI
- [ ] **REQ-OBR-17** — Dashboard SRE: SLOs e Error Budget
- [ ] **REQ-OBR-18** — Relatório: como o MTTR é reduzido

**💰 FinOps**

- [ ] **REQ-OBR-19** — Política de tags no Terraform
- [ ] **REQ-OBR-20** — Rightsizing de requests/limits
- [ ] **REQ-OBR-21** — Forecast de custos mensais
- [ ] **REQ-OBR-22** — ≥ 1 recomendação de otimização nativa

**🤖 ITSM e AIOps**

- [ ] **REQ-OBR-23** — IA do APM detectando anomalias
- [ ] **REQ-OBR-24** — Ciclo de vida do incidente desenhado

**🛟 Multicloud, Segurança e DR**

- [ ] **REQ-OBR-25** — Documento executivo de PCN
- [ ] **REQ-OBR-26** — RTO e RPO dos dados de doação
- [ ] **REQ-OBR-27** — Estratégia de DR implementada

**📦 Entregáveis**

- [ ] **REQ-OBR-28** — Regra de avaliação: mostrar funcionando
- [ ] **REQ-OBR-29** — Repositório: Terraform com tags FinOps
- [ ] **REQ-OBR-30** — Repositório: YAML com requests/limits
- [ ] **REQ-OBR-31** — Repositório: pipelines com DevSecOps
- [ ] **REQ-OBR-32** — Vídeo de até 20 minutos
- [ ] **REQ-OBR-33** — Pitch executivo para a diretoria
- [ ] **REQ-OBR-34** — Demo: CI/CD rodando + deploy via ArgoCD
- [ ] **REQ-OBR-35** — Demo: Terraform rodando / recursos com tags
- [ ] **REQ-OBR-36** — Demo: traces no APM e alertas
- [ ] **REQ-OBR-37** — Demo: Dashboard SRE com SLOs calculados
- [ ] **REQ-OBR-38** — Demo: Backup/DR em ação
- [ ] **REQ-OBR-39** — Relatório em PDF
- [ ] **REQ-OBR-40** — Relatório: nomes, RMs e usernames
- [ ] **REQ-OBR-41** — Relatório: links do repositório e do vídeo
- [ ] **REQ-OBR-42** — Seção SRE: SLI, SLO e SLA formais
- [ ] **REQ-OBR-43** — Seção FinOps: Forecast + evidência de tags
- [ ] **REQ-OBR-44** — Seção Segurança e DR: PCN + estratégia
- [ ] **REQ-OBR-45** — Seção ITSM/AIOps: ciclo de incidentes

**⏱️ Transversal**

- [ ] **REQ-OBR-46** — Desenvolvimento em grupo
- [ ] **REQ-OBR-47** — Entrega dentro do prazo

## 8. Dúvidas para o tutor

| ID | Dúvida [INCERTO] | Evidência e leitura adotada | Afeta |
|---|---|---|---|
| <a id="q-01"></a>Q-01 | O vídeo tem “até 20 min”, mas o Pitch Executivo é descrito como “15 a 20 min” e ainda há a Demo Tech. A demo faz parte do pitch, dentro dos 20 minutos? | p. 6. Leitura adotada: um único vídeo de 15–20 min com a demo embutida; nunca passar de 20 min. | REQ-OBR-32, REQ-OBR-33 |
| <a id="q-02"></a>Q-02 | A p. 6 se chama “ENTREGÁVEIS DA FASE 4”. É erro de digitação (Fase 5)? | p. 6. Leitura adotada: entregáveis do Hackathon Fase 5. | — |
| <a id="q-03"></a>Q-03 | “Prometheus, Grafana, Loki e/ou OpenTelemetry”: qual é a stack mínima aceita? O OTel Collector continua obrigatório como na Fase 4? | p. 4. Leitura conservadora: manter a stack completa da Fase 4 (Regra de Ouro, p. 2). | REQ-OBR-12 |
| <a id="q-04"></a>Q-04 | A p. 3 aceita ArgoCD ou FluxCD, mas a demo pede deploy “via ArgoCD”. FluxCD é aceito na gravação? | p. 3 e 6. ArgoCD elimina a dúvida. | REQ-OBR-11, REQ-OBR-34 |
| <a id="q-05"></a>Q-05 | Entrega individual é aceita? Qual o tamanho do grupo? | p. 2: “em princípio” em grupo. | REQ-OBR-46 |
| <a id="q-06"></a>Q-06 | Quais são as datas de início e fim do Hackathon de 2 meses corridos? | p. 2 cita o prazo sem data. | REQ-OBR-47 |
| <a id="q-07"></a>Q-07 | Em que plataforma e de que forma a entrega é submetida? | Não consta nas p. 2–7; o Discord aparece apenas para dúvidas (p. 7). | REQ-OBR-47 |
| <a id="q-08"></a>Q-08 | Existe peso por frente ou rubrica detalhada? Quanto vale cada dedução? | p. 3 cita 5 frentes; p. 6 cita dedução direta, sem valores. | — |
| <a id="q-09"></a>Q-09 | As automações de incidente da Fase 4 (PagerDuty/OpsGenie, ChatOps, Self-Healing) precisam ser reaplicadas ao novo ecossistema? | p. 2 (Regra de Ouro), p. 4 (MTTR cita automações), p. 6 (alertas na demo). Tratado como obrigatório [INCERTO]. | REQ-OBR-14 |
| <a id="q-10"></a>Q-10 | As três tags (Project, Environment, CostCenter) são exatamente as exigidas? Qual valor de Environment para a região de DR? E recursos que não aceitam tags? | p. 4: tags obrigatórias “como” as três citadas; “todos os recursos”. | REQ-OBR-19 |
| <a id="q-11"></a>Q-11 | Basta ativar o recurso de IA do APM ou é preciso mostrar uma anomalia detectada? Ele está disponível nas contas gratuitas/educacionais? (AIOps não aparece nas listas do vídeo e do relatório.) | p. 5 exige a ativação; p. 6–7 não listam AIOps no vídeo; a regra geral exige evidência (p. 6). As aulas não citam Watchdog nem Applied Intelligence. | REQ-OBR-23 |
| <a id="q-12"></a>Q-12 | O Welcome anuncia ITIL e ISO/IEC 20000, mas as oito aulas de ITSM e AIOps não os abordam. Há material complementar? O ciclo de vida do incidente deve seguir algum framework? | Welcome p. 3; aulas 1–8 do módulo; o enunciado (p. 5) não exige framework. O guia usa SRE (Aulas 4–5) + AIOps (Aulas 1 e 8) e um complemento de ITIL 4. | REQ-OBR-24, REQ-OBR-45 |
| <a id="q-13"></a>Q-13 | “Backup/DR em ação” exige restore/failover real, ou basta mostrar o backup e os módulos prontos? O bucket “externo” precisa estar em outra região/provedor? | p. 5 (opções A/B) e p. 6 (exemplo: mostrar Velero ou módulos prontos). | REQ-OBR-27, REQ-OBR-38 |
| <a id="q-14"></a>Q-14 | O que se espera do SLA (público, metas, consequências)? Ele só aparece na seção do relatório. | p. 3 (SLO/SLA com ONGs) e p. 7 (SLI, SLO e SLA formais); a p. 4 cita só SLI/SLO. | REQ-OBR-42 |
| <a id="q-15"></a>Q-15 | Os usernames do relatório são de qual plataforma (portal FIAP, GitHub, Discord)? | p. 7 não especifica. | REQ-OBR-40 |
| <a id="q-16"></a>Q-16 | Qual horizonte e qual base do Forecast (meses, custos reais ou estimados, ferramenta)? | p. 4 pede “projeção de custos mensais”, sem horizonte nem ferramenta. | REQ-OBR-21 |
| <a id="q-17"></a>Q-17 | O código usa SQS e DynamoDB (AWS). AKS/GKE são aceitos mesmo assim, consumindo serviços AWS entre nuvens? | p. 3 permite EKS, AKS ou GKE; o repositório-fonte é acoplado à AWS. | REQ-OBR-06 |
| <a id="q-18"></a>Q-18 | O Dashboard SRE deve ser “exclusivamente” SLO/Error Budget (p. 4), mas a demo pede “Golden Metrics e SLOs calculados” (p. 6). Golden Metrics no mesmo painel são aceitas? | p. 4 e 6. Leitura adotada: painel SRE com SLIs (derivados das Golden Metrics), metas e budget. | REQ-OBR-17, REQ-OBR-37 |
| <a id="q-19"></a>Q-19 | Que critério define “Dockerfile otimizado” (multi-stage, tamanho, usuário não root, zero CVEs críticas)? | p. 3; o README do repositório cita multi-stage e redução de vulnerabilidades. | REQ-OBR-05 |
| <a id="q-20"></a>Q-20 | O repositório-fonte não traz testes. Que nível de teste se espera no pipeline (unitário, integração, smoke)? | p. 3 exige testes; o repositório-fonte não os contém. | REQ-OBR-08 |
| <a id="q-21"></a>Q-21 | A Opção B chama de Warm Standby um ambiente que se levanta “com 1 comando”. Na aula de DR, Warm Standby já fica ligado em capacidade mínima; subir sob demanda se aproxima de Pilot Light ou Backup & Restore. Qual leitura vale para a avaliação? | Enunciado p. 5; Multicloud e Segurança, Aula 5, p. 9–11. Declare no PCN o padrão realmente adotado e o RTO correspondente. | REQ-OBR-27 |
| <a id="q-22"></a>Q-22 | Itens do README do repositório-fonte (ElastiCache, Budgets) são exigidos ou opcionais? | O enunciado (fonte normativa) não os lista; tratados como bônus. | — |

## 9. Índice dos guias de estudo

| # | Guia | Aulas | Páginas |
|---|---|:-:|:-:|
| 00 | [Welcome to Multicloud, custos e IA](../aulas-fiap/00.Welcome%20to%20Multicloud%2C%20custos%20e%20IA/GUIA-ESTUDO-Welcome-to-Multicloud-custos-e-IA.html) | 1 | 4 |
| 01 | [Multicloud e Segurança](../aulas-fiap/01.Multicloud%20e%20Seguran%C3%A7a/GUIA-ESTUDO-Multicloud-e-Seguranca.html) | 8 | 148 |
| 02 | [SRE — Site Reliability Engineering](../aulas-fiap/02.SRE%20%28Site%20Reliability%20Engineering%29/GUIA-ESTUDO-SRE-Site-Reliability-Engineering.html) | 5 | 83 |
| 03 | [FinOps](../aulas-fiap/03.FinOps/GUIA-ESTUDO-FinOps.html) | 6 | 89 |
| 04 | [IT Service Management e AIOps](../aulas-fiap/04.IT%20Service%20Management%20e%20AIOPs/GUIA-ESTUDO-IT-Service-Management-e-AIOps.html) | 8 | 168 |

---
Gerado em 2026-11-11 a partir do enunciado do Hackathon Fase 5 (p. 2–7), do [repositório-fonte oficial](https://github.com/dougls/hackathon-DCLT) e das aulas da fase. Conteúdo idêntico ao de [REQUISITOS.html](REQUISITOS.html).
