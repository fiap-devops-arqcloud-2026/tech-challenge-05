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

# Mostra a senha inicial do usuário admin, que o ArgoCD gera no primeiro start (não fica no estado do Terraform); a senha sai em texto no terminal, então não rode com a tela gravada.
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Depois de trocar a senha do admin (na interface: User Info > Update Password), apaga o Secret que guarda a senha inicial em texto.
kubectl -n argocd delete secret argocd-initial-admin-secret
```

A conta `admin` fica ligada (padrão do chart) e controla tudo o que o ArgoCD
aplica no cluster. A documentação do Argo CD recomenda trocar a senha inicial
e apagar o `argocd-initial-admin-secret`, que só existe para guardá-la em
texto; o ArgoCD o recria se for preciso gerar outra senha. Como cada cluster
novo gera uma senha nova, repita os dois passos a cada janela de trabalho.
Nenhum dos dois é deploy: os objetos da aplicação continuam vindo só do
GitOps.

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

# Aplica o plano revisado: a Application sai primeiro, o ArgoCD apaga os recursos que ela gerencia (os declarados no Git) e depois sai o namespace solidarytech, com o que sobrou nele.
terraform apply k8s-destroy.tfplan

# Confere que não sobrou volume persistente antes de destruir o cluster (a lista deve vir vazia; um PV em Released some sozinho em instantes, enquanto o driver apaga o disco).
kubectl get pv

# Se a lista acima não vier vazia: mostra os PVCs que ainda existem e o namespace de cada um.
kubectl get pvc -A

# Apaga cada PVC listado, com o driver EBS CSI ainda no ar; o PV (reclaim Delete) e o disco EBS saem junto.
kubectl delete pvc <nome-do-pvc> -n <namespace>
```

A Application tem o finalizer `resources-finalizer.argocd.argoproj.io`: o
uninstall espera (até 10 minutos) o ArgoCD remover os recursos que ela
gerencia, ou seja, os declarados no Git. Na Fase 4, sem essa ordem, discos EBS
de PVCs ficaram órfãos depois do destroy, cobrando. Se o ArgoCD não conseguir
apagar algum recurso, o destroy para por timeout; corrija a causa e rode plan
e apply de destroy de novo.

O finalizer **não** cobre os PVCs criados pelo `volumeClaimTemplates` de um
StatefulSet (Prometheus e Loki, por exemplo): eles não são recursos da
Application, e o Kubernetes os mantém quando o StatefulSet sai (retenção
padrão `whenDeleted: Retain`). No namespace `solidarytech`, eles saem com o
namespace, que esta raiz apaga. Num namespace criado pelo ArgoCD, como o da
observabilidade, eles sobrevivem ao destroy desta raiz, e os discos ficam
órfãos depois do destroy do cluster; por isso a conferência acima. Para evitar
o caso, os StatefulSets do GitOps devem declarar
`persistentVolumeClaimRetentionPolicy.whenDeleted: Delete`, ou o namespace
deles deve ser declarado no Git (aí ele sai junto com a Application).

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
