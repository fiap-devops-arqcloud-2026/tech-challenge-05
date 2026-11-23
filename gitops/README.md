# GitOps da SolidaryTech

O cluster reflete só o que está neste diretório: o ArgoCD aplica o overlay
`overlays/prod` no namespace `solidarytech`, com sincronização automática,
`prune` e `selfHeal`. Nada de `kubectl apply` manual: toda mudança na
aplicação é um commit.

## O que fica aqui e o que fica no Terraform

| Objeto | Dono | Por quê |
|---|---|---|
| Deployments, Services, PDB, Job de schema, gerador de tráfego | **GitOps** (este diretório) | Descrevem a aplicação e mudam a cada versão |
| Namespace `solidarytech`, Secrets dos bancos, ConfigMap `aws-endpoints`, ServiceAccounts com IRSA, StorageClass gp3 | **Terraform** (`terraform/k8s`) | Dependem de valores da AWS (endpoint do RDS, URL da fila, ARNs das roles) e de senhas geradas |
| Application `solidarytech` do ArgoCD | **Terraform** (`terraform/k8s`) | É criada só depois que as imagens existem no ECR (`enable_applications = true`) |

Um objeto nunca tem dois donos: se o mesmo Secret estivesse aqui e no
Terraform, os dois ficariam se desfazendo. A validação abaixo reprova
qualquer um desses objetos neste diretório.

## Estrutura

```text
gitops/
├── base/
│   ├── ngo-service/          # Deployment, Service
│   ├── donation-service/     # Deployment (2 réplicas), Service, PodDisruptionBudget
│   ├── volunteer-service/    # Deployment, Service
│   ├── db-schema/            # Job PreSync: bancos, usuários e schemas no RDS
│   └── traffic-generator/    # tráfego sintético contínuo (liga e desliga por réplicas)
└── overlays/prod/            # namespace e imagens publicadas (o CI reescreve a tag)
```

## Como uma versão nova chega ao cluster

1. Um push na `main` que altera um serviço passa pelos gates do CI (testes,
   lint, SAST, SCA e scan da imagem).
2. O CI publica a imagem no ECR com a tag igual ao SHA do commit.
3. O CI grava essa tag em `overlays/prod/kustomization.yaml` num commit do
   robô.
4. O ArgoCD detecta o commit e aplica: primeiro o Job de schema (hook
   PreSync, idempotente), depois os Deployments, com atualização sem queda.

Voltar uma versão é reverter o commit do robô.

## Decisões que valem saber

- **Schema sem kubectl.** O Job `db-schema` cria `ngo_db` e `donation_db`,
  com um usuário por serviço (`ngo_app`, `donation_app`), e aplica os
  `init.sql` do coordenador só quando a tabela ainda não existe. Ele roda a
  cada sincronização e é idempotente; cada usuário conecta só no próprio
  banco. Os arquivos de `db-schema/sql/` são cópias exatas de
  `services/*/db/init.sql`, porque o Kustomize só lê arquivos dentro da
  própria pasta; a validação reprova se a cópia divergir.
- **ID da conta no overlay.** O endereço do ECR inclui o ID da conta AWS. A
  AWS não trata o ID de conta como segredo, o acesso continua protegido por
  IAM e OIDC, e o Kustomize não permite separar o registro da tag (um
  override só de nome apaga a tag). Por isso o endereço fica só no overlay,
  gravado pelo robô do CI.
- **Segurança dos Pods.** Usuário não root com UID fixo, disco somente
  leitura, sem escalonamento de privilégio, todas as capabilities
  removidas, seccomp `RuntimeDefault` e sem token da API do Kubernetes. A
  credencial da AWS chega por IRSA, nunca por chave.
- **Requests e limits** são o ponto de partida; o ajuste fino é feito com
  métricas reais na camada de FinOps, sempre por commit.

## Validar antes de commitar

```bash
# Render com o mesmo Kustomize do ArgoCD, schema estrito, boas práticas, shellcheck e regras de dono
bash scripts/gitops/validate.sh
```

O mesmo script roda no CI. Ele precisa de Docker e não acessa cluster nem
conta AWS.
