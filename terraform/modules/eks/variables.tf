# =================================================================
# VARIÁVEIS DE ENTRADA — módulo eks
# =================================================================
# Nenhuma variável tem valor padrão: quem chama o módulo declara o que
# quer. Os padrões do projeto ficam em terraform/cluster/variables.tf,
# onde a decisão está documentada. Módulo com padrão escondido cria
# recurso diferente do esperado em silêncio.
# =================================================================

variable "cluster_name" {
  description = "Nome do cluster EKS (padrão do projeto: <projeto>-eks). Entra no kubeconfig, no ARN do cluster e na policy do self-healing."
  type        = string

  validation {
    # Regra do próprio EKS: até 100 caracteres, começando por letra ou
    # dígito, com letras, dígitos, hífen ou sublinhado.
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "O nome do cluster aceita até 100 caracteres: letras, dígitos, hífen ou sublinhado, começando por letra ou dígito."
  }
}

variable "name_prefix" {
  description = "Prefixo dos nomes das roles IAM do módulo (ex.: solidarytech gera solidarytech-eks-cluster-role)."
  type        = string
}

variable "kubernetes_version" {
  description = "Versão maior.menor do Kubernetes do control plane e dos nós (ex.: 1.37)."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Informe só a versão maior.menor do Kubernetes, como 1.37."
  }
}

variable "subnet_ids" {
  description = "Sub-redes PRIVADAS da raiz base, onde ficam as interfaces do control plane e os nós. O EKS exige pelo menos duas, em AZs diferentes."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "O EKS exige pelo menos duas sub-redes, em zonas de disponibilidade diferentes."
  }
}

variable "endpoint_public_access_cidrs" {
  description = "Blocos CIDR que alcançam o endpoint público da API do Kubernetes."
  type        = list(string)

  validation {
    condition     = length(var.endpoint_public_access_cidrs) > 0 && alltrue([for cidr in var.endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Informe ao menos um bloco CIDR válido, como 203.0.113.10/32."
  }
}

variable "node_group_name" {
  description = "Nome do node group gerenciado (padrão do projeto: <projeto>-nodes). Também nomeia o launch template e a tag Name das instâncias."
  type        = string
}

variable "node_instance_type" {
  description = "Tipo EC2 dos nós (ex.: m7i-flex.large). A arquitetura precisa ser x86_64, a da AMI AL2023_x86_64_STANDARD."
  type        = string
}

variable "node_desired_size" {
  description = "Número de nós desejado no node group."
  type        = number
}

variable "node_min_size" {
  description = "Número mínimo de nós no node group."
  type        = number

  validation {
    condition     = var.node_min_size >= 1 && floor(var.node_min_size) == var.node_min_size
    error_message = "node_min_size precisa ser um inteiro maior ou igual a 1."
  }
}

variable "node_max_size" {
  description = "Número máximo de nós no node group."
  type        = number

  validation {
    # As validações podem citar outras variáveis desde o Terraform 1.9;
    # assim a combinação inválida falha no plano, e não no meio do apply.
    condition     = var.node_max_size >= var.node_min_size && var.node_desired_size >= var.node_min_size && var.node_desired_size <= var.node_max_size
    error_message = "Os tamanhos precisam respeitar node_min_size <= node_desired_size <= node_max_size."
  }
}

variable "node_disk_size_gb" {
  description = "Tamanho, em GiB, do disco raiz gp3 de cada nó."
  type        = number

  validation {
    # O snapshot da AMI AL2023 do EKS tem 20 GiB; um disco menor que o
    # snapshot faz a instância falhar ao subir.
    condition     = var.node_disk_size_gb >= 20 && floor(var.node_disk_size_gb) == var.node_disk_size_gb
    error_message = "O disco dos nós precisa ser um inteiro de pelo menos 20 GiB (tamanho do snapshot da AMI AL2023)."
  }
}

variable "node_tags" {
  description = <<-EOT
    Tags gravadas nas instâncias e nos volumes dos nós pelo launch
    template. São as tags obrigatórias do projeto: o node group não
    propaga as próprias tags para as instâncias, e o default_tags do
    provider não alcança recursos criados pelo Auto Scaling do EKS.
  EOT
  type        = map(string)

  validation {
    # Sem estas três chaves, o custo dos nós (o maior item da conta) some
    # do filtro por tag do Budget e do Cost Explorer.
    condition     = alltrue([for key in ["Project", "Environment", "CostCenter"] : contains(keys(var.node_tags), key)])
    error_message = "node_tags precisa conter as tags obrigatórias Project, Environment e CostCenter."
  }
}
