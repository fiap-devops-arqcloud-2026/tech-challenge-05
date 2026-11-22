# =================================================================
# IDENTIDADE DA CONTA — raiz bootstrap
# =================================================================
# Consultas somente leitura: não criam nada na AWS.
#
# O ID da conta e a partição entram no nome do bucket e no ARN do
# provedor OIDC importado. Lidos em tempo de execução, eles não precisam
# ficar escritos em nenhum arquivo versionado do repositório público.
# =================================================================

# Conta e identidade das credenciais em uso. O provider já garante, por
# allowed_account_ids, que é a conta esperada.
data "aws_caller_identity" "current" {}

# Partição da AWS ("aws" na nuvem comercial). Montar ARNs com ela, em vez
# de escrever "arn:aws:" fixo, mantém o código correto em outras partições.
data "aws_partition" "current" {}
