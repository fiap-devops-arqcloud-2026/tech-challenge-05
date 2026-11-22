# =================================================================
# BUCKET DE ESTADO DO TERRAFORM
# =================================================================
# Guarda os estados de todas as raízes (phase5/prod/<raiz>.tfstate).
#
# POR QUE TANTO CUIDADO COM UM BUCKET
# O estado do Terraform guarda em TEXTO PURO tudo o que os recursos
# devolvem, inclusive a senha mestre do RDS e as senhas dos usuários dos
# bancos (o "sensitive" só esconde do terminal). Quem lê o bucket lê os
# segredos. Por isso: acesso público bloqueado, cifragem, só HTTPS e
# versionamento para desfazer um estado corrompido.
#
# Na Fase 4 este bucket foi criado à mão antes do primeiro init. Aqui ele
# nasce do código, e o estado do próprio bootstrap é migrado para ele
# depois do primeiro apply (ver README.md).
# =================================================================

locals {
  # Conta e região no nome tornam o nome único no mundo (o namespace de
  # buckets do S3 é global) e deixam claro de onde ele é.
  state_bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  # ARN montado a partir do nome, e não lido do recurso: assim a policy
  # já é conhecida no plan e pode ser revisada (e testada) antes do apply.
  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.state_bucket_name}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # Proteção do único recurso que não é efêmero no projeto: com false, o
  # destroy FALHA enquanto houver qualquer objeto ou versão no bucket, em
  # vez de apagar os estados junto. Para encerrar o projeto, o bucket é
  # esvaziado de propósito antes (ver README.md).
  force_destroy = false
}

# Desliga as ACLs: o dono do bucket é dono de todo objeto e o acesso passa
# a depender só de IAM e da bucket policy (recomendação atual da AWS).
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Os quatro bloqueios de acesso público. Mesmo que alguém escreva por
# engano uma policy ou ACL pública, a AWS a ignora ou recusa.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cada gravação do estado vira uma versão nova: um apply que corrompa o
# estado pode ser desfeito restaurando a versão anterior.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cifragem em repouso com chave gerenciada pelo S3 (SSE-S3). Uma chave
# KMS própria daria controle de acesso extra, mas custa por mês e por
# requisição, sem ganho real para um projeto deste porte.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Policy que NEGA qualquer acesso sem TLS. Um Deny explícito vence
# qualquer Allow, então nem um administrador consegue ler o estado (e as
# senhas dentro dele) por HTTP em texto claro.
data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    # "*" aqui é o alvo da NEGAÇÃO (todo mundo), não uma permissão.
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    # O bucket em si e todos os objetos dentro dele.
    resources = [
      local.state_bucket_arn,
      "${local.state_bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json

  # Policy e bloqueio público alteram a mesma configuração do bucket. Em
  # paralelo, a AWS pode responder "OperationAborted: A conflicting
  # conditional operation is currently in progress"; em sequência, não.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# Limpeza automática para o versionamento não acumular custo para sempre.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expira-versoes-antigas-e-uploads-incompletos"
    status = "Enabled"

    # Filtro vazio: a regra vale para todos os objetos do bucket.
    filter {}

    # Versões substituídas ficam 90 dias: tempo de sobra para notar e
    # desfazer um estado ruim, sem guardar o histórico inteiro.
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Uploads em partes interrompidos não aparecem na listagem, mas são
    # cobrados. Sete dias depois, a AWS os descarta.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A documentação do provider pede o versionamento ligado ANTES das regras
  # sobre versões não correntes; sem depends_on, os dois rodariam juntos.
  depends_on = [aws_s3_bucket_versioning.state]
}
