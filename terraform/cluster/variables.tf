# =================================================================
# VARIÁVEIS DE ENTRADA — raiz cluster
# =================================================================
# As três primeiras se repetem em todas as raízes: são root modules
# independentes, e um não lê as variáveis do outro (só o estado, por
# terraform_remote_state, em data.tf).
#
# Sem valor padrão, de propósito: expected_aws_account_id, state_bucket
# e state_region. Vêm do terraform.tfvars local (ignorado pelo Git) ou de
# TF_VAR_<nome>, para que nenhum identificador da conta vá para o Git.
# =================================================================

# -----------------------------------------------------------------
# COMUNS A TODAS AS RAÍZES
# -----------------------------------------------------------------

variable "project_name" {
  description = "Prefixo dos nomes dos recursos (roles, node group, RDS). O mesmo valor em todas as raízes."
  type        = string
  default     = "solidarytech"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "Use de 3 a 21 caracteres: uma letra minúscula no início, depois letras minúsculas, dígitos ou hífen."
  }
}

variable "aws_region" {
  description = "Região AWS desta raiz. Precisa ser a mesma da raiz base (conferido em data.tf)."
  type        = string
  default     = "us-east-2"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "Informe o código de uma região da AWS, como us-east-2."
  }
}

variable "expected_aws_account_id" {
  description = "ID da conta AWS do projeto (12 dígitos). O provider recusa credenciais de qualquer outra conta. Vem do terraform.tfvars local ou de TF_VAR_expected_aws_account_id, nunca do Git."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "Informe o ID da conta AWS com exatamente 12 dígitos."
  }
}

# -----------------------------------------------------------------
# ESTADO DA RAIZ BASE
# -----------------------------------------------------------------

variable "state_bucket" {
  description = "Bucket S3 dos estados (saída state_bucket_name do bootstrap); o mesmo do backend.hcl. Daqui esta raiz lê o estado da base."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "Informe um nome de bucket S3 válido: 3 a 63 caracteres entre minúsculas, dígitos, ponto e hífen."
  }

  validation {
    # O allowed_account_ids protege só o provider AWS, não a leitura do
    # terraform_remote_state. O bucket do projeto fica no namespace
    # regional da conta (<projeto>-tfstate-<conta>-<região>-an), e o S3 só
    # deixa a própria conta criar um bucket com esse sufixo. Exigir o
    # sufixo com a conta esperada e a região do bucket garante que o
    # estado lido é desta conta, e não de um bucket alheio com nome
    # parecido.
    condition     = endswith(var.state_bucket, "-${var.expected_aws_account_id}-${var.state_region}-an")
    error_message = "O bucket de estado precisa estar no namespace regional da conta esperada: o nome termina em -<conta>-<região do bucket>-an, como em <projeto>-tfstate-<conta>-<região>-an."
  }
}

variable "state_region" {
  description = "Região do bucket de estado (saída state_bucket_region do bootstrap); a mesma do backend.hcl."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.state_region))
    error_message = "Informe o código de uma região da AWS, como us-east-2."
  }
}

# -----------------------------------------------------------------
# CLUSTER EKS
# -----------------------------------------------------------------

variable "kubernetes_version" {
  description = <<-EOT
    Versão do Kubernetes do EKS. A 1.37 era a versão padrão do EKS em
    us-east-2 na leitura da conta de 2026-11-20, com suporte padrão até
    2027-11-30. O cluster usa upgrade_policy STANDARD: ao fim do suporte
    padrão, o EKS atualiza a versão em vez de cobrar o suporte estendido.
  EOT
  type        = string
  default     = "1.37"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Informe só a versão maior.menor do Kubernetes, como 1.37."
  }
}

variable "node_instance_type" {
  description = <<-EOT
    Tipo EC2 dos nós. m7i-flex.large (2 vCPU, 8 GiB, x86_64), o mesmo da
    Fase 4: está entre os tipos elegíveis ao plano gratuito da conta, que
    recusa os demais. Nós de 8 GiB foram a resposta da Fase 4 à memória
    apertada com a stack de observabilidade.
  EOT
  type        = string
  default     = "m7i-flex.large"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.node_instance_type))
    error_message = "Informe um tipo de instância EC2, como m7i-flex.large."
  }
}

variable "node_desired_size" {
  description = "Nós desejados. 2 nós, um por AZ na distribuição do Auto Scaling, dão onde reagendar os Pods se um nó cair; 4 vCPU cabem com folga na cota de 16 vCPU da conta."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= var.node_min_size && var.node_desired_size <= var.node_max_size
    error_message = "node_desired_size precisa ficar entre node_min_size e node_max_size."
  }
}

variable "node_min_size" {
  description = "Mínimo de nós. Igual ao desejado: não há Cluster Autoscaler, e o node group não deve encolher abaixo de dois nós."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_size >= 1 && floor(var.node_min_size) == var.node_min_size
    error_message = "node_min_size precisa ser um inteiro maior ou igual a 1."
  }
}

variable "node_max_size" {
  description = "Máximo de nós: folga de um nó para um aumento manual de capacidade (desired_size), sem passar de 6 vCPU."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= var.node_min_size && floor(var.node_max_size) == var.node_max_size
    error_message = "node_max_size precisa ser um inteiro maior ou igual a node_min_size."
  }
}

variable "node_disk_size_gb" {
  description = "Disco raiz gp3 cifrado de cada nó, em GiB. 20 GiB é o tamanho do snapshot da AMI AL2023 e o padrão do EKS."
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size_gb >= 20 && var.node_disk_size_gb <= 100 && floor(var.node_disk_size_gb) == var.node_disk_size_gb
    error_message = "O disco dos nós precisa ser um inteiro de 20 a 100 GiB."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    Blocos CIDR que alcançam o endpoint público da API do Kubernetes. O
    padrão 0.0.0.0/0 é deliberado: o workflow de self-healing roda em
    runners hospedados do GitHub, com IPs que mudam a cada execução, e
    precisa chamar a API do cluster. A API continua exigindo credencial
    AWS válida e uma access entry. Restringir a lista (ao IP de quem
    opera, por exemplo) corta o self-healing.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Informe ao menos um bloco CIDR válido, como 203.0.113.10/32."
  }
}

# -----------------------------------------------------------------
# BANCO DE DADOS (RDS PostgreSQL)
# -----------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe do RDS. db.t4g.micro (Graviton, 2 vCPU, 1 GiB): oferece o PostgreSQL 17 em us-east-2 (leitura da conta de 2026-11-20) e custa menos por hora que a db.t3.micro da Fase 4."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "Informe uma classe do RDS, como db.t4g.micro."
  }
}

variable "db_engine_version" {
  description = <<-EOT
    Versão MAIOR do PostgreSQL: 17, a mesma do PostgreSQL do Compose
    local. Só a maior, de propósito: o RDS escolhe a versão menor e a
    atualiza sozinho (auto_minor_version_upgrade), e o Terraform não
    tenta desfazer essas atualizações no plano seguinte.
  EOT
  type        = string
  default     = "17"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.db_engine_version))
    error_message = "Informe só a versão maior do PostgreSQL, como 17."
  }
}

variable "db_allocated_storage_gb" {
  description = "Armazenamento gp3 cifrado do RDS, em GiB. 20 GiB é o mínimo do gp3 no RDS."
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage_gb >= 20 && var.db_allocated_storage_gb <= 100 && floor(var.db_allocated_storage_gb) == var.db_allocated_storage_gb
    error_message = "O armazenamento do RDS precisa ser um inteiro de 20 a 100 GiB."
  }
}

variable "db_backup_retention_days" {
  description = <<-EOT
    Retenção dos backups automáticos do RDS, em dias. É também a janela
    da restauração para um ponto no tempo (PITR), base da proteção dos
    dados de doação na estratégia de DR. 0 desligaria os dois e é
    recusado. Se o plano gratuito da conta recusar 7 dias no apply
    (FreeTierRestrictionError), use 1 (README.md).
  EOT
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35 && floor(var.db_backup_retention_days) == var.db_backup_retention_days
    error_message = "A retenção de backup precisa ser um inteiro de 1 a 35 dias (0 desligaria o PITR)."
  }
}

# -----------------------------------------------------------------
# APLICAÇÃO
# -----------------------------------------------------------------

variable "app_namespace" {
  description = "Namespace Kubernetes da aplicação. Entra na condição sub das roles IRSA; a raiz k8s cria o namespace e as ServiceAccounts com este mesmo nome."
  type        = string
  default     = "solidarytech"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.app_namespace))
    error_message = "O namespace precisa ser um nome DNS válido do Kubernetes (minúsculas, dígitos e hífen, até 63 caracteres)."
  }
}
