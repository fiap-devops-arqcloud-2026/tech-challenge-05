# Raiz `bootstrap`

Cria o que as outras raízes do Terraform precisam antes de existir e que
sobrevive aos destroys de cada janela de uso:

| Recurso | Para quê |
|---|---|
| Bucket S3 `<projeto>-tfstate-<conta>-<região>-an` | Guarda os estados de todas as raízes. Fica no namespace regional da conta (`bucket_namespace = "account-regional"`): só esta conta consegue criar um bucket com esse sufixo. Versionado, cifrado (SSE-S3), sem acesso público, sem ACLs, só HTTPS, com limpeza de versões antigas (90 dias) e de uploads incompletos (7 dias). Protegido por `force_destroy = false` e `prevent_destroy = true`. |
| Provedor OIDC do GitHub | Permite ao GitHub Actions obter credenciais temporárias da AWS sem chave guardada. A conta já tem o provedor: ele é **adotado** por um bloco `import`, sem ser recriado. |
| Budget `<projeto>-mensal` | Teto de US$ 50/mês filtrado pela tag `Project=SolidaryTech`, com alertas por e-mail no gasto real (50%, 80%, 100%) e na previsão (100%). Mede o custo bruto: créditos e reembolsos não entram, senão o alerta nunca dispararia numa conta paga por créditos. A previsão só existe depois de cerca de 5 semanas de custo com a tag: até lá, quem protege são os alertas do gasto real. |
| Tags de alocação de custo | Ativa `Project`, `Environment` e `CostCenter` no faturamento. Desligado no início (ver abaixo). |

Na Fase 4 esses itens foram criados à mão, no console ou na CLI. Aqui eles
são código, como pede a regra de zero infraestrutura clicada.

## Por que duas etapas

O backend S3 desta raiz aponta para um bucket que ela mesma cria. No primeiro
apply o bucket não existe, então o estado começa **local** (um arquivo
`backend_override.tf`, que o Git ignora pela regra `*_override.tf`) e é
migrado para o bucket logo depois, na chave `phase5/prod/bootstrap.tfstate`.

Pré-requisitos: Terraform 1.11 ou mais novo (o projeto usa 1.16.0), AWS CLI
com credenciais de um usuário IAM administrador da conta do projeto e
autorização do responsável pela conta para o apply. Os comandos abaixo são
para o Git Bash, a partir da raiz do repositório.

## Etapa 1 — primeiro apply, com estado local

```bash
# Entra na pasta desta raiz.
cd terraform/bootstrap

# Cria o tfvars local (ignorado pelo Git); edite a conta e o e-mail reais antes de seguir.
cp terraform.tfvars.example terraform.tfvars

# Troca o backend S3 (o bucket ainda não existe) por estado local; *_override.tf é ignorado pelo Git.
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf

# Baixa o provider travado no .terraform.lock.hcl e prepara o estado local.
terraform init

# Gera o plano salvo. Esperado: "Plan: 1 to import, 8 to add, 1 to change, 0 to destroy" (bucket e 6 configurações, Budget, provedor OIDC adotado).
terraform plan -out=bootstrap.tfplan

# Aplica exatamente o plano revisado.
terraform apply bootstrap.tfplan
```

No plano, o provedor OIDC aparece como importado com uma atualização no
lugar só nas tags (sai a tag da Fase 4, entram as obrigatórias): é o
`1 to change`. Qualquer `must be replaced` nele é motivo para parar e revisar.

## Etapa 2 — migrar o estado para o bucket

```bash
# Gera o backend.hcl local (ignorado pelo Git) com o bucket e a região recém-criados; precisa do estado local, então vem antes de remover o override.
printf 'bucket = "%s"\nregion = "%s"\n' "$(terraform output -raw state_bucket_name)" "$(terraform output -raw state_bucket_region)" > backend.hcl

# Remove o override: a raiz volta a usar o backend S3 declarado em versions.tf.
rm backend_override.tf

# Copia o estado local para phase5/prod/bootstrap.tfstate no bucket; responda "yes" quando o init perguntar se deve copiar o estado.
terraform init -migrate-state -backend-config=backend.hcl

# Confere que o estado agora vem do S3: o plano deve dizer "No changes".
terraform plan -out=bootstrap.tfplan

# Apaga o plano e as cópias locais do estado, que não servem mais (o estado vive no bucket).
rm -f bootstrap.tfplan terraform.tfstate terraform.tfstate.backup
```

O mesmo `backend.hcl` (bucket e região) serve para as raízes `base`,
`cluster` e `k8s`, e os mesmos valores vão em `state_bucket` e
`state_region` nos tfvars de `cluster` e `k8s`. Todos esses arquivos são
locais: o nome do bucket contém o ID da conta.

## Uso depois da migração

```bash
# Numa cópia nova do repositório: cria o backend.hcl local a partir do exemplo e preenche o bucket real.
cp backend.hcl.example backend.hcl

# Inicializa já apontando para o bucket.
terraform init -backend-config=backend.hcl

# Todo apply passa por um plano salvo e revisado.
terraform plan -out=bootstrap.tfplan

# Aplica o plano revisado.
terraform apply bootstrap.tfplan
```

## Tags de alocação de custo

O filtro por tag do Budget e o custo por tag no Cost Explorer só enxergam o
gasto depois que `Project`, `Environment` e `CostCenter` são **ativadas** como
tags de alocação de custo. São duas esperas: a chave leva até 24 horas para
aparecer no faturamento depois de aplicada ao primeiro recurso, e a ativação
leva até mais 24 horas para valer depois do pedido. O custo de antes da
ativação não entra no filtro, a não ser por backfill. Se a ativação ficar para
depois da primeira janela do cluster, o Budget não vê o custo mais caro do
projeto e a evidência de custo por tag perde esse período.

A ordem recomendada é aplicar o bootstrap pelo menos um dia antes da primeira
janela do cluster (o bucket tagueado já leva as chaves ao faturamento) e
ativar as tags antes de subir a base e o cluster:

```bash
# Confere, só lendo, se as três chaves já aparecem no faturamento como tags do usuário ainda inativas.
aws ce list-cost-allocation-tags --status Inactive --type UserDefined

# Com as chaves listadas, troque activate_cost_allocation_tags para true no terraform.tfvars e gere o plano salvo.
terraform plan -out=bootstrap.tfplan

# Aplica o plano revisado; a ativação ainda leva até 24 horas para valer.
terraform apply bootstrap.tfplan

# Opcional: traz para o filtro por tag o custo desde o primeiro dia de um mês dos últimos 12 (uma vez a cada 24 horas).
aws ce start-cost-allocation-tag-backfill --backfill-from AAAA-MM-01T00:00:00Z
```

Até a ativação valer, o Budget não vê o custo do projeto; o custo anterior a
ela só entra no filtro por backfill.

## Encerramento do projeto

O bootstrap só é destruído no fim do projeto, depois de `k8s`, `cluster` e
`base`. O bucket tem duas travas, que protegem os estados de um destroy
acidental:

- `force_destroy = false`: a exclusão falha enquanto houver qualquer versão de
  objeto dentro dele;
- `lifecycle { prevent_destroy = true }`: o próprio plano de destroy para com
  `Instance cannot be destroyed`, antes de apagar qualquer coisa.

O encerramento esvazia o bucket e desliga a segunda trava **de propósito**,
com um arquivo de override local (`state_bucket_override.tf`, ignorado pelo
Git pela regra `*_override.tf`), sem mudar o `state-bucket.tf` versionado.

Antes de começar, colete as evidências de custo por tag (Cost Explorer) e do
Budget: o destroy apaga o Budget e devolve `Project`, `Environment` e
`CostCenter` ao estado inativo no faturamento (é o que o provider faz ao
destruir `aws_ce_cost_allocation_tag`).

A sequência roda no Git Bash, numa pasta já inicializada com o backend S3, com
autorização do responsável pela conta:

```bash
# Volta o estado desta raiz para um arquivo local, porque o bucket que o guarda vai ser apagado.
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf

# Copia o estado do S3 para o arquivo local; responda "yes" à pergunta de cópia.
terraform init -migrate-state

# Guarda o nome do bucket numa variável do shell para os próximos comandos.
BUCKET="$(terraform output -raw state_bucket_name)"

# Apaga todas as versões e marcadores de exclusão (os estados antigos); confira antes que as outras raízes já foram destruídas. O tr tira o \r que a AWS CLI do Windows põe no fim de cada linha (sem ele, cada version-id sai inválido), e o laço para no primeiro erro.
aws s3api list-object-versions --bucket "$BUCKET" --query '[Versions,DeleteMarkers][].[Key,VersionId]' --output text | tr -d '\r' | while IFS=$'\t' read -r key version; do aws s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$version" || break; done

# Confere que o bucket ficou vazio: a saída precisa vir vazia; se listar algum par chave e versão, repita o comando anterior antes de seguir.
aws s3api list-object-versions --bucket "$BUCKET" --query '[Versions,DeleteMarkers][].[Key,VersionId]' --output text | tr -d '\r'

# Opcional, só se as tags foram ativadas por esta raiz: para mantê-las ativas depois do encerramento, tira-as do estado sem desativá-las na AWS.
terraform state rm 'aws_ce_cost_allocation_tag.required'

# Desliga de propósito o prevent_destroy do bucket, sem mudar o arquivo versionado.
printf 'resource "aws_s3_bucket" "state" {\n  lifecycle {\n    prevent_destroy = false\n  }\n}\n' > state_bucket_override.tf

# Gera o plano de destroy salvo para revisão.
terraform plan -destroy -out=bootstrap-destroy.tfplan

# Aplica o plano de destroy revisado.
terraform apply bootstrap-destroy.tfplan

# Religa a trava para um eventual bootstrap novo e apaga o plano aplicado.
rm -f state_bucket_override.tf bootstrap-destroy.tfplan
```

Sem o bucket vazio, a exclusão dele falha com `BucketNotEmpty`, mas só depois
de o mesmo apply ter apagado a policy de TLS, o bloqueio público, o provedor
OIDC e o Budget; por isso a conferência antes do plano. Mesmo depois de
apagado, o nome continua no namespace regional desta conta: nenhuma outra
conta consegue criá-lo.

Depois do destroy, o provedor OIDC deixa de existir: volte
`import_existing_github_oidc_provider` para `false` antes de um novo apply,
senão o plan falha com `Cannot import non-existent remote object`. Se outro
projeto da conta passar a usar o provedor, tire-o do estado antes do destroy
com um bloco `removed` (explicado em `github-oidc.tf`), para não apagá-lo.

## Verificação offline

Sem credenciais e sem custo; é o que o CI pode rodar a cada alteração.

```bash
# Baixa o provider sem configurar o backend (não acessa o S3).
terraform -chdir=terraform/bootstrap init -backend=false -input=false

# Confere sintaxe, tipos e referências.
terraform -chdir=terraform/bootstrap validate

# Roda os testes de tests/bootstrap.tftest.hcl (provider apontado para uma porta fechada).
terraform -chdir=terraform/bootstrap test
```
