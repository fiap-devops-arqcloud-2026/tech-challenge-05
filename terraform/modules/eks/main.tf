# =================================================================
# MÓDULO EKS — control plane e provedor OIDC do cluster
# =================================================================
# Adaptado do módulo da Fase 4, que rodou de verdade na AWS. O que mudou
# na Fase 5, e por quê:
#
#   - authentication_mode "API": quem entra no cluster é decidido só por
#     access entries da API do EKS, criadas pelo Terraform. O ConfigMap
#     aws-auth (editado à mão, fora do código) deixa de ser aceito. A
#     Fase 4 usava API_AND_CONFIG_MAP, mas o código dela já concedia
#     acesso só por access entries;
#   - upgrade_policy STANDARD: ao fim do suporte padrão, o EKS atualiza o
#     control plane em vez de passar a cobrar o suporte estendido, em que
#     a hora do control plane sobe de US$ 0,10 para US$ 0,60;
#   - versão do Kubernetes e CIDRs do endpoint público por variável;
#   - node group com launch template próprio (nodes.tf);
#   - versões dos addons resolvidas pela AWS na hora do plano (addons.tf);
#   - roles com sufixo "-role"/"-irsa": na Fase 4, o nome do cluster foi
#     confundido com o da role do control plane, e o ARN errado quase
#     entrou na policy do self-healing.
#
# Arquivos do módulo:
#   main.tf   — role do control plane, cluster e provedor OIDC (IRSA);
#   nodes.tf  — role dos nós, launch template e node group;
#   addons.tf — role IRSA do driver EBS CSI e addons gerenciados.
#
# Tags: nenhum recurso daqui declara tags. O default_tags do provider da
# raiz aplica as obrigatórias a tudo o que o Terraform cria; a exceção
# (instâncias e volumes dos nós) está tratada no launch template.
#
# Textos enviados à AWS (descriptions) ficam sem acento de propósito:
# alguns campos da API aceitam só ASCII e recusam o recurso inteiro.
# =================================================================

# Partição da AWS ("aws" nas regiões comerciais). Monta os ARNs das
# policies gerenciadas sem fixar "arn:aws:" no código.
data "aws_partition" "current" {}

locals {
  # Endereço do emissor OIDC sem o "https://". É o prefixo das chaves de
  # condição (<emissor>:sub e <emissor>:aud) das trusts IRSA.
  oidc_issuer = trimprefix(aws_iam_openid_connect_provider.cluster.url, "https://")
}

# -----------------------------------------------------------------
# ROLE DO CONTROL PLANE
# -----------------------------------------------------------------
# O control plane é operado pela AWS em nome da conta; para isso o
# serviço EKS assume esta role.
# -----------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    sid     = "EksServiceAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      # Só o serviço EKS pode assumir a role; nenhum usuário ou outro
      # serviço da AWS.
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  description        = "Assumida pelo servico EKS para operar o control plane do cluster ${var.cluster_name}."
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

# Policy gerenciada pela AWS: acompanha as mudanças do serviço sem que o
# projeto precise reescrever permissões a cada versão do EKS.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------
# O CLUSTER
# -----------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    # Sub-redes privadas: as interfaces de rede do control plane e os nós
    # ficam sem IP público.
    subnet_ids = var.subnet_ids

    # Endpoint privado: os nós falam com a API sem sair da VPC.
    endpoint_private_access = true

    # Endpoint público: necessário para o Terraform e o kubectl de quem
    # opera e para o workflow de self-healing, que roda em runners do
    # GitHub. Expõe só a API do Kubernetes (não os serviços da
    # aplicação), e ela exige credencial AWS válida e uma access entry.
    endpoint_public_access = true
    public_access_cidrs    = var.endpoint_public_access_cidrs

    # Sem security_group_ids: o EKS cria o security group do cluster e o
    # anexa ao control plane e aos nós. O RDS libera a porta 5432 só para
    # esse grupo (ver nodes.tf e o módulo rds).
  }

  access_config {
    authentication_mode = "API"

    # Dá acesso de administrador a quem roda o apply. Sem isto, nem quem
    # criou o cluster consegue usar o kubectl depois (e a raiz k8s, que
    # usa a mesma identidade, não consegue criar nada).
    bootstrap_cluster_creator_admin_permissions = true
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  # Ambiente efêmero: o cluster é destruído ao fim de cada janela de
  # trabalho. A proteção contra exclusão faria o destroy falhar.
  deletion_protection = false

  # Sem enabled_cluster_log_types: os logs do control plane no CloudWatch
  # são cobrados por GB ingerido e armazenado, e nenhum requisito do
  # projeto depende deles. Os Secrets do Kubernetes já são cifrados em
  # repouso pelo EKS (criptografia envelope padrão, com chave gerenciada
  # pela AWS), o que dispensa uma chave KMS própria, cobrada por mês.

  # A policy precisa estar anexada antes de o EKS assumir a role: sem o
  # depends_on, os dois poderiam ser criados em paralelo e o cluster
  # falhar por falta de permissão. No destroy, a ordem se inverte e a
  # policy só é retirada depois que o cluster já foi apagado.
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# -----------------------------------------------------------------
# PROVEDOR OIDC DO CLUSTER (base do IRSA)
# -----------------------------------------------------------------
# Permite que um Pod troque o token da sua ServiceAccount por credenciais
# temporárias da AWS (sts:AssumeRoleWithWebIdentity). É o que elimina
# chaves de acesso estáticas em Secrets. Não confundir com o provedor
# OIDC do GitHub (raiz bootstrap), que autentica o CI.
# -----------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  # Público do token projetado pelo EKS para IRSA: valor fixo.
  client_id_list = ["sts.amazonaws.com"]

  # Sem thumbprint_list, de propósito: o IAM valida o emissor do EKS pela
  # própria lista de autoridades certificadoras confiáveis e, quando o
  # campo não é informado, obtém sozinho a impressão digital do
  # certificado. A Fase 4 calculava esse valor com o provider tls, que
  # deixa de ser necessário.
}
