# =================================================================
# RAIZ BASE — variáveis de entrada
# =================================================================
# Só expected_aws_account_id é obrigatória: vem do terraform.tfvars local
# (ignorado pelo Git) ou de TF_VAR_expected_aws_account_id, nunca do Git.
# As demais têm o padrão do projeto; o terraform.tfvars.example mostra o
# que dá para ajustar. As validações barram valores inválidos já no plan,
# com mensagem clara, em vez de deixar a API da AWS recusá-los no apply.
# =================================================================

# -----------------------------------------------------------------
# Comuns a todas as raízes
# -----------------------------------------------------------------

variable "project_name" {
  description = "Prefixo dos nomes de recurso (VPC, repositórios ECR e roles do CI)."
  type        = string
  nullable    = false
  default     = "solidarytech"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name deve ter de 3 a 21 caracteres (minúsculas, números e hífen), começando por letra."
  }
}

variable "aws_region" {
  description = "Região AWS da infraestrutura principal."
  type        = string
  nullable    = false
  default     = "us-east-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region deve ser um código de região da AWS, como us-east-2."
  }
}

variable "expected_aws_account_id" {
  description = "ID de 12 dígitos da única conta AWS em que esta raiz pode operar; o provider recusa credenciais de outra conta."
  type        = string
  nullable    = false
  # Sem default de propósito: o ID real não entra no Git.

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "expected_aws_account_id deve ter exatamente 12 dígitos."
  }
}

# -----------------------------------------------------------------
# Rede
# -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC. As sub-redes /24 são calculadas a partir dele (ver main.tf)."
  type        = string
  nullable    = false
  default     = "10.0.0.0/16"

  # O plano de sub-redes usa blocos /24 nas posições 1, 101 e 201 da VPC,
  # o que exige um /16, também o maior bloco que a AWS aceita numa VPC.
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("^[0-9.]+/16$", var.vpc_cidr))
    error_message = "vpc_cidr deve ser um bloco IPv4 /16, como 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Zonas de disponibilidade. Cada uma recebe uma sub-rede pública, uma privada e uma de banco."
  type        = list(string)
  nullable    = false
  default     = ["us-east-2a", "us-east-2b"]

  # O EKS e o DB subnet group do RDS exigem sub-redes em pelo menos duas
  # zonas.
  validation {
    condition     = length(var.azs) >= 2 && length(distinct(var.azs)) == length(var.azs)
    error_message = "Informe ao menos duas zonas de disponibilidade distintas."
  }

  # Evita trocar a região (para a de DR, por exemplo) e esquecer as zonas.
  validation {
    condition     = alltrue([for az in var.azs : can(regex("^${var.aws_region}[a-z]$", az))])
    error_message = "Todas as zonas devem pertencer à região de aws_region (ex.: us-east-2a para us-east-2)."
  }
}

variable "enable_nat_gateway" {
  description = "Liga o NAT Gateway único. Com o cluster no ar, ele é obrigatório; sem cluster, false corta o maior custo fixo da base."
  type        = bool
  nullable    = false
  # true para nunca deixar o cluster sem saída por esquecimento: sem NAT,
  # os nós das sub-redes privadas não baixam imagens do ECR (os Pods
  # ficam em ImagePullBackOff), não obtêm credenciais do STS para o IRSA e
  # a observabilidade não alcança os serviços externos.
  default = true
}

# -----------------------------------------------------------------
# Aplicação
# -----------------------------------------------------------------

variable "services" {
  description = "Serviços da aplicação. Cada um ganha um repositório ECR <project_name>/<serviço>."
  type        = list(string)
  nullable    = false
  # Os nomes completos (com -service) são os mesmos dos Deployments e das
  # ServiceAccounts no Kubernetes.
  default = ["ngo-service", "donation-service", "volunteer-service"]

  validation {
    condition     = length(var.services) > 0 && length(distinct(var.services)) == length(var.services)
    error_message = "Informe ao menos um serviço, sem repetição."
  }

  validation {
    condition     = alltrue([for s in var.services : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", s))])
    error_message = "Cada serviço deve usar só letras minúsculas, números e hífens simples (ex.: ngo-service)."
  }
}

variable "sqs_queue_name" {
  description = "Nome da fila Standard das doações; a DLQ recebe o sufixo -dlq. É o nome usado na documentação do projeto."
  type        = string
  nullable    = false
  default     = "solidary-donations"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,76}$", var.sqs_queue_name))
    error_message = "sqs_queue_name deve ter de 1 a 76 caracteres (letras, números, hífen e sublinhado)."
  }
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB dos voluntários, exigido pela documentação do projeto e lido pelo volunteer-service."
  type        = string
  nullable    = false
  default     = "SolidaryTechVolunteers"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,255}$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name deve ter de 3 a 255 caracteres (letras, números, ponto, hífen e sublinhado)."
  }
}

variable "eks_cluster_name" {
  description = "Nome do cluster EKS criado pela raiz cluster. A base o usa para montar o ARN do cluster na policy do self-healing."
  type        = string
  nullable    = false
  # A base nasce antes do cluster e não pode ler o estado dele: o ARN é
  # montado a partir deste nome previsível. Ele precisa ser o nome exato
  # do cluster; um nome parecido (como o de uma role) geraria um ARN que
  # não casa com nada, e o self-healing receberia AccessDenied.
  default = "solidarytech-eks"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.eks_cluster_name))
    error_message = "eks_cluster_name deve ter de 1 a 100 caracteres (letras, números, hífen e sublinhado), começando por letra ou número."
  }
}

# -----------------------------------------------------------------
# Identidade do CI no GitHub
# -----------------------------------------------------------------
# Os IDs não são credenciais: aparecem na API pública do GitHub e no
# próprio token OIDC. Ao reaproveitar a base em outro repositório,
# conferir os dois (GET /repos/<owner>/<repo>: campos owner.id e id).

variable "github_repository" {
  description = "Repositório autorizado a assumir as roles do CI via OIDC, no formato owner/repo."
  type        = string
  nullable    = false
  default     = "fiap-devops-arqcloud-2026/tech-challenge-05"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository deve ser owner/repo, sem curingas nem contexto OIDC."
  }
}

variable "github_repository_owner_id" {
  description = "ID numérico imutável do dono do repositório GitHub (parte do subject OIDC)."
  # Texto com só dígitos, e não number: preserva o valor exato e deixa a
  # validação recusar curingas.
  type     = string
  nullable = false
  default  = "287716251"

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id deve ser um ID numérico positivo do GitHub."
  }
}

variable "github_repository_id" {
  description = "ID numérico imutável do repositório GitHub (parte do subject OIDC)."
  type        = string
  nullable    = false
  default     = "1454212968"

  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.github_repository_id))
    error_message = "github_repository_id deve ser um ID numérico positivo do GitHub."
  }
}

variable "github_deploy_branch" {
  description = "Branch exata cujos workflows podem assumir as roles do CI e do self-healing."
  type        = string
  nullable    = false
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", var.github_deploy_branch))
    error_message = "github_deploy_branch deve ser um nome de branch explícito, sem curingas, dois-pontos ou espaços."
  }
}
