# =================================================================
# PROVIDERS — raiz k8s
# =================================================================
# aws: guarda de conta (allowed_account_ids) e tags, como nas demais
#      raízes;
# kubernetes e helm: falam com a API do EKS, com endereço e certificado
#      lidos do estado da raiz cluster (data.tf).
# =================================================================

locals {
  # Política de tags do FinOps, idêntica em todas as raízes. Aqui ela
  # também vai para os volumes EBS criados pela StorageClass
  # (storageclass.tf), que o default_tags do provider AWS não alcança.
  required_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }

  # Argumentos do "aws eks get-token", iguais nos dois providers abaixo.
  eks_get_token_args = [
    "eks",
    "get-token",
    "--cluster-name",
    local.cluster_name,
    "--region",
    var.aws_region,
  ]
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_aws_account_id]

  default_tags {
    tags = local.required_tags
  }
}

# -----------------------------------------------------------------
# KUBERNETES
# -----------------------------------------------------------------
# AUTENTICAÇÃO POR TOKEN TEMPORÁRIO: a cada operação o provider executa a
# AWS CLI e recebe um token do EKS válido por 15 minutos. Nada de
# kubeconfig ou credencial gravada em disco; vale a identidade IAM já
# configurada na máquina (quem criou o cluster é administrador dele).
#
# Requisito: a AWS CLI instalada e no PATH.
#
# LIMITE CONHECIDO (Fase 4): allowed_account_ids protege só o provider
# AWS. O token do EKS e a leitura dos estados remotos usam a cadeia
# padrão de credenciais da máquina; como nenhum provider aqui fixa um
# perfil, todos usam a mesma identidade.
# -----------------------------------------------------------------
provider "kubernetes" {
  host = local.cluster_endpoint

  # O EKS entrega o certificado da CA em base64.
  cluster_ca_certificate = base64decode(local.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_get_token_args
  }
}

# -----------------------------------------------------------------
# HELM
# -----------------------------------------------------------------
# Mesmo acesso do provider kubernetes. ATENÇÃO À SINTAXE da linha 3.x:
# "kubernetes = { ... }" e "exec = { ... }" levam sinal de igual. Escrever
# "kubernetes { ... }" como bloco falha o validate com "Blocks of type
# kubernetes are not expected here" (tropeço registrado na Fase 4).
# -----------------------------------------------------------------
provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_get_token_args
    }
  }
}
