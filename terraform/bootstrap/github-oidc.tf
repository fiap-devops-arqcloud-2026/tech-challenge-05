# =================================================================
# PROVEDOR OIDC DO GITHUB — confiança entre o GitHub Actions e a AWS
# =================================================================
# Com o provedor registrado na conta, o workflow troca um token assinado
# pelo GitHub por credenciais temporárias da AWS. Não existe chave de
# acesso guardada no GitHub: nada para vazar, girar ou revogar.
#
# Este arquivo só registra o GitHub como emissor confiável. QUEM pode
# assumir QUAL role (repositório, branch) fica na trust das roles, na
# raiz base (módulo iam-ci), que lê este provedor por data source.
#
# RECURSO GLOBAL E ÚNICO: existe um provedor por URL na conta inteira (a
# AWS recusa um segundo com EntityAlreadyExists). A conta do projeto já o
# tem desde a Fase 4, criado no console; aqui ele é ADOTADO pelo código
# com um bloco import, sem ser recriado, e o CI nunca fica sem acesso.
# =================================================================

resource "aws_iam_openid_connect_provider" "github" {
  # Emissor dos tokens do GitHub Actions. Fixo; não é parametrizável.
  url = "https://token.actions.githubusercontent.com"

  # Público (claim "aud") esperado no token. É o valor que a action
  # aws-actions/configure-aws-credentials solicita ao GitHub.
  client_id_list = ["sts.amazonaws.com"]

  # A AWS valida o GitHub pela própria cadeia de autoridades
  # certificadoras confiáveis e, na prática, ignora este campo. O valor
  # padrão é o que já está gravado no provedor da conta: com ele, o import
  # não mostra diferença aqui (só nas tags) e nada é substituído.
  thumbprint_list = var.github_oidc_thumbprints

  # Tags: vêm do default_tags do provider. No primeiro plan, o import
  # mostra a troca da tag herdada da Fase 4 pelas tags obrigatórias, uma
  # atualização no lugar.
}

# -----------------------------------------------------------------
# IMPORT CONDICIONAL
# -----------------------------------------------------------------
# Um bloco import diz ao Terraform: "este recurso já existe com este ID;
# adote-o no estado em vez de criá-lo". O plan mostra "will be imported";
# depois do apply, rodar o plan de novo não importa nada outra vez.
#
# O for_each de zero ou um elemento é o liga/desliga, no mesmo padrão
# validado num apply real na Fase 4:
#   - conjunto com um elemento -> importa o recurso (que não tem índice);
#   - conjunto vazio           -> nenhum import; o apply CRIA o provedor.
#
# Depois de um destroy do bootstrap, o provedor deixa de existir e a
# variável precisa voltar a false; senão o plan falha com "Cannot import
# non-existent remote object".
#
# ATENÇÃO NO ENCERRAMENTO: com o provedor no estado, o destroy do
# bootstrap o apaga. Se outro projeto da conta passar a depender dele,
# troque antes o resource por um bloco
#   removed { from = aws_iam_openid_connect_provider.github
#             lifecycle { destroy = false } }
# que tira o provedor do estado sem apagá-lo da AWS.
# -----------------------------------------------------------------
import {
  for_each = var.import_existing_github_oidc_provider ? toset(["github"]) : toset([])
  to       = aws_iam_openid_connect_provider.github

  # O ID de importação é o ARN, montado com a conta das credenciais em
  # uso (nenhum número de conta escrito no repositório).
  id = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
