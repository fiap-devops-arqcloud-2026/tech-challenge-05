# =================================================================
# VERSÕES E BACKEND — raiz bootstrap
# =================================================================
# O bootstrap cria o que as outras raízes precisam ANTES de existir: o
# bucket que guarda os estados, o provedor OIDC do GitHub (importado da
# conta) e o Budget. Na Fase 4 esses itens nasceram no console; aqui eles
# vêm do código, para cumprir a regra de zero infraestrutura clicada.
#
# O PROBLEMA DO OVO E DA GALINHA
# O backend abaixo aponta para um bucket que esta própria raiz cria. No
# primeiro apply o bucket ainda não existe, então o estado começa LOCAL
# (arquivo backend_override.tf, ignorado pelo Git) e é migrado para o
# bucket logo depois, com:
#
#   terraform init -migrate-state -backend-config=backend.hcl
#
# O passo a passo completo, com os dois momentos, está no README.md.
# =================================================================

terraform {
  # 1.11 é a primeira versão com o use_lockfile do backend S3 (trava por
  # objeto .tflock, sem tabela DynamoDB). O teto evita que uma versão 2.x,
  # com mudanças incompatíveis, entre sem revisão.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.73" aceita correções e novas versões menores da linha 6, mas
      # não a 7. A versão exata fica travada no .terraform.lock.hcl, que é
      # versionado para todos usarem o mesmo binário.
      version = "~> 6.73"
    }
  }

  # Backend PARCIAL: só a chave fica no código. Bucket e região vêm do
  # backend.hcl local (ignorado pelo Git), para nenhum identificador da
  # conta ir para o repositório público.
  backend "s3" {
    key = "phase5/prod/bootstrap.tfstate"

    # Cifra o objeto do estado no S3 (o bucket também cifra por padrão;
    # aqui a exigência fica explícita do lado do cliente).
    encrypt = true

    # Trava nativa do S3: impede dois applies simultâneos no mesmo estado.
    use_lockfile = true
  }
}
