# =================================================================
# MÓDULO ECR — um repositório de imagens por serviço
# =================================================================
# O pipeline de CI constrói a imagem de cada serviço e a publica aqui; o
# EKS baixa as imagens daqui. Os repositórios ficam no namespace do
# projeto (<project_name>/<serviço>), o que agrupa as imagens no console
# e deixa claro a que projeto cada uma pertence.
# =================================================================

resource "aws_ecr_repository" "this" {
  # Um repositório por serviço. toset() porque o for_each exige conjunto;
  # cada instância fica endereçável pelo nome do serviço, por exemplo
  # aws_ecr_repository.this["ngo-service"].
  for_each = toset(var.services)

  name = "${var.project_name}/${each.value}"

  # IMMUTABLE: uma tag publicada nunca muda de conteúdo. O CI publica só
  # tags com o SHA do commit, e o GitOps aponta para essas tags; com a tag
  # imutável, ninguém troca a imagem por baixo de uma versão já implantada
  # (proteção da cadeia de suprimentos). Efeito colateral: reexecutar o
  # pipeline no mesmo commit não pode sobrescrever a tag, então o CI deve
  # pular o push quando a imagem já existir.
  image_tag_mutability = var.image_tag_mutability

  # Ambiente efêmero: o destroy precisa apagar o repositório mesmo com
  # imagens dentro. Sem isso, o destroy falha e alguém tem de esvaziar o
  # repositório à mão.
  force_delete = true

  image_scanning_configuration {
    # Scan básico e gratuito a cada push: uma segunda camada além do scan
    # do pipeline, que cobre também uma imagem enviada fora do CI.
    scan_on_push = true
  }

  encryption_configuration {
    # AES256 usa chave gerenciada pelo próprio ECR, sem custo. Com KMS,
    # haveria cobrança por requisição sem ganho para este projeto.
    encryption_type = "AES256"
  }
}

# -----------------------------------------------------------------
# Expiração de imagens antigas
# -----------------------------------------------------------------
# Cada commit gera uma imagem nova, e o armazenamento do ECR é cobrado por
# GB-mês. Sem esta política, o repositório cresce para sempre. O GitOps
# aponta sempre para a imagem mais recente; as anteriores ficam como
# margem de rollback até serem expiradas.
# -----------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  # Mesmas chaves do recurso acima: o "ngo-service" daqui é o de lá.
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        # Texto sem acentos de propósito: ele vai para a API da AWS, e
        # algumas APIs recusam caracteres fora do ASCII em descrições.
        description = "Mantem apenas as ${var.images_to_keep} imagens mais recentes"
        selection = {
          # "any": conta imagens com e sem tag.
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.images_to_keep
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
