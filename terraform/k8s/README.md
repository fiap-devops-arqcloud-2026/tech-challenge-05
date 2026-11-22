# Raiz `k8s`

Cria, dentro do EKS, os objetos que dependem de valores da AWS e instala o
ArgoCD. Assim nenhum ID de conta, endereço de banco ou senha precisa ir para
os manifestos do repositório público: o GitOps só referencia nomes.

| Objeto | Nome | Conteúdo |
|---|---|---|
| Namespace | `solidarytech` (output `app_namespace` da raiz cluster) | Rótulo `app.kubernetes.io/part-of=solidarytech` |
| StorageClass padrão | `gp3` | EBS CSI, gp3 cifrado, `WaitForFirstConsumer`, `Delete`, expansão permitida e as tags do FinOps nos volumes (`tagSpecification_1..4`) |
| Secret | `ngo-service-db` | `DATABASE_URL` (`postgresql://ngo_app:...@<rds>:5432/ngo_db?sslmode=require`) |
| Secret | `donation-service-db` | `DATABASE_URL` (`postgres://donation_app:...@<rds>:5432/donation_db?sslmode=require`) |
| Secret | `db-schema` | `PGHOST`, `PGPORT`, `PGUSER` e `PGPASSWORD` (mestre), `PGSSLMODE=require`, `NGO_APP_PASSWORD`, `DONATION_APP_PASSWORD` |
| ConfigMap | `aws-endpoints` | `AWS_REGION`, `AWS_SQS_URL`, `AWS_DYNAMODB_TABLE` |
| ServiceAccount | `donation-service`, `volunteer-service` | Anotação `eks.amazonaws.com/role-arn` (IRSA) |
| ServiceAccount | `ngo-service` | Sem role e sem token montado |
| Helm release | `argocd` (namespace `argocd`) | Chart `argo-cd` 10.18.2 (Argo CD v3.6.2), Dex e notifications desligados, ApplicationSet com zero réplicas, recursos pequenos, servidor `ClusterIP` |
| Helm release | `argocd-apps` | Application `solidarytech` com sincronização automática (`prune`, `selfHeal`, `retry`); só com `enable_applications = true` |

As senhas dos usuários de aplicação nascem aqui (`random_password`, 24
caracteres alfanuméricos); a senha mestre vem do estado da raiz cluster. Os
serviços recebem só o próprio usuário; a senha mestre vai apenas para o Job de
schema.

## Pré-requisitos

- Raízes `bootstrap`, `base` e `cluster` aplicadas: esta raiz lê
  `phase5/prod/base.tfstate` e `phase5/prod/cluster.tfstate`.
- AWS CLI no `PATH`: os providers `kubernetes` e `helm` se autenticam com
  `aws eks get-token`, com a mesma identidade IAM que criou o cluster.
- Autorização do responsável pela conta para o apply.

## Aplicar

Comandos para o Git Bash, a partir da raiz do repositório.

```bash
# Entra na pasta desta raiz.
cd terraform/k8s

# Cria o tfvars local (ignorado pelo Git); preencha a conta e o bucket reais.
cp terraform.tfvars.example terraform.tfvars

# Cria o backend.hcl local (ignorado pelo Git); preencha o bucket real (output state_bucket_name do bootstrap).
cp backend.hcl.example backend.hcl

# Inicializa com o backend S3 (chave phase5/prod/k8s.tfstate).
terraform init -backend-config=backend.hcl

# Gera o plano salvo para revisão.
terraform plan -out=k8s.tfplan

# Aplica exatamente o plano revisado.
terraform apply k8s.tfplan
```

Um apply só instala o ArgoCD e, com `enable_applications = true`, a
Application. Na Fase 4 eram dois (o primeiro com `-target`), porque o
`kubernetes_manifest` exigia a CRD já instalada no plan; o chart `argocd-apps`
não tem essa limitação.

**Quando ligar a Application.** Deixe `enable_applications = false` até que a
pasta `gitops/overlays/prod` exista na `main` e as imagens estejam publicadas
no ECR. Depois, troque para `true` no `terraform.tfvars` e faça plan e apply.

## Acessar o ArgoCD

Não há Ingress nem Load Balancer: o acesso é por túnel local.

```bash
# Configura o kubectl desta máquina para o cluster (grava o acesso no kubeconfig local).
aws eks update-kubeconfig --region us-east-2 --name solidarytech-eks

# Abre a interface em http://localhost:8080 (Ctrl+C fecha o túnel).
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Mostra a senha inicial do usuário admin, que o ArgoCD gera no primeiro start (não fica no estado do Terraform).
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Contrato com o GitOps

- Os manifestos em `gitops/` **não declaram** o namespace `solidarytech` nem
  os Secrets, o ConfigMap, as ServiceAccounts e a StorageClass desta raiz. Se
  declararem, ArgoCD e Terraform passam a disputar os mesmos objetos.
- Os Deployments referenciam esses objetos por nome: `serviceAccountName`,
  `secretKeyRef` (`DATABASE_URL`) e `configMapKeyRef`/`envFrom`
  (`aws-endpoints`).
- O Job de schema conecta como usuário mestre pelas variáveis `PG*` do Secret
  `db-schema`, cria os bancos `ngo_db` e `donation_db` e os usuários
  `ngo_app` e `donation_app`, e **define a senha a cada execução**
  (`ALTER ROLE ... PASSWORD`). As senhas mudam se esta raiz for destruída e
  recriada com o RDS de pé.
- Se algum Deployment ganhar HPA, a Application precisa de
  `ignoreDifferences` em `/spec/replicas` (ver `argocd.tf`).

## Destruir

Sempre **antes** do destroy da raiz cluster.

```bash
# Gera o plano de destroy salvo para revisão.
terraform plan -destroy -out=k8s-destroy.tfplan

# Aplica o plano revisado: a Application sai primeiro e o ArgoCD apaga tudo o que ela criou, inclusive PVCs (e os discos EBS), antes de ser desinstalado.
terraform apply k8s-destroy.tfplan

# Confere que não sobrou volume persistente antes de destruir o cluster (a lista deve vir vazia).
kubectl get pv
```

A Application tem o finalizer `resources-finalizer.argocd.argoproj.io`: o
uninstall espera (até 10 minutos) o ArgoCD remover os recursos dela. Na Fase 4,
sem essa ordem, discos EBS de PVCs ficaram órfãos depois do destroy, cobrando.
Se o ArgoCD não conseguir apagar algum recurso, o destroy para por timeout;
corrija a causa e rode plan e apply de destroy de novo.

## Verificação offline

Sem credenciais, sem cluster e sem custo.

```bash
# Baixa os providers sem configurar o backend (não acessa o S3).
terraform -chdir=terraform/k8s init -backend=false -input=false

# Confere sintaxe, tipos e referências.
terraform -chdir=terraform/k8s validate

# Roda os testes de tests/k8s.tftest.hcl (providers simulados e estados remotos fictícios).
terraform -chdir=terraform/k8s test
```
