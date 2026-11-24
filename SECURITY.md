# Política de segurança

Premissa do projeto: **nenhuma credencial estática de nuvem**. O pipeline de CI
entra na AWS por OIDC e os Pods, por IRSA. Não há chave de acesso da AWS no
repositório, nos segredos do GitHub nem dentro do cluster.

Senhas de banco são geradas pelo Terraform e entregues aos Pods por Secret do
Kubernetes. Chaves de serviços externos (APM, gestão de incidentes, chat) são
criadas pelos integrantes e ficam num `.env` local, fora do Git.

## Como as credenciais funcionam

| Quem precisa de acesso | Como obtém | O que NÃO existe |
|---|---|---|
| Pipeline de CI, para publicar imagens no ECR | OpenID Connect: o GitHub Actions troca o token da execução por credencial temporária da AWS | `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` nos segredos do repositório |
| Pods, para usar a fila SQS e a tabela DynamoDB | IRSA: cada Pod recebe credencial temporária ligada à sua própria ServiceAccount | Chave de acesso dentro de Secret do Kubernetes |
| Serviços, para falar com o PostgreSQL | Senha gerada pelo Terraform, entregue por Secret do Kubernetes | Senha escrita à mão em arquivo |
| Integrantes, para aplicar o Terraform | Perfil local da AWS CLI, com sessão temporária | Credencial em arquivo do repositório |

A política de confiança das roles do CI aceita apenas tokens da branch `main`
deste repositório, identificado pelos IDs numéricos do dono e do repositório no
GitHub. Token de outro repositório, de outra branch ou de pull request é
recusado.

## Nunca versionar

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` ou `AWS_SESSION_TOKEN` reais
- Senha ou string de conexão real de banco
- License key do APM, chave de integração da ferramenta de incidentes, webhook do chat, tokens do GitHub
- `.env`, `terraform.tfstate`, `*.tfvars`, `*.tfplan`, `backend.hcl`, kubeconfig, certificados e chaves privadas

O estado do Terraform guarda senhas **em texto puro**. Por isso ele vive num
bucket S3 privado, versionado, criptografado e que só aceita TLS, criado pela
raiz `terraform/bootstrap/`.

## Antes de cada push

```bash
# Varre os arquivos versionados atrás de chaves, tokens e arquivos proibidos; sai com erro se encontrar algo
bash scripts/security-check.sh
```

```bash
# Mostra exatamente o que vai para o próximo commit: a verificação mais barata que existe
git diff --cached
```

A mesma varredura roda no CI. O CI é a segunda linha de defesa: quando ele
acusa, o segredo já está num commit enviado ao GitHub e precisa ser revogado.

## Se uma credencial vazar

1. **Revogue imediatamente** no serviço de origem. Trocar o arquivo não basta:
   a credencial continua válida até ser revogada.
2. Remova do histórico do Git. Apagar do arquivo e commitar por cima **não**
   remove: o valor continua acessível nos commits anteriores.
3. Gere uma credencial nova e confirme que a antiga não funciona mais.
