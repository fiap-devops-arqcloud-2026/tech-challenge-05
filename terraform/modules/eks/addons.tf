# =================================================================
# ADDONS GERENCIADOS — e a role IRSA do driver EBS CSI
# =================================================================
# Addon gerenciado é um componente que a AWS instala e atualiza no
# cluster. Os cinco abaixo são os mesmos da Fase 4; instalá-los como
# addon, e não por Helm, mantém esta raiz sem os providers kubernetes e
# helm.
#
# Novo na Fase 5: a versão de cada addon vem do data source
# aws_eks_addon_version com most_recent = true, isto é, a mais recente
# compatível com a versão do Kubernetes do cluster, consultada na hora
# do plano. Na Fase 4 a versão ficava a critério do EKS e não aparecia
# no plano; agora ela aparece no plano salvo, que é revisado antes do
# apply.
# =================================================================

locals {
  # Nomes oficiais dos addons na API do EKS.
  addon_names = toset([
    "vpc-cni",
    "kube-proxy",
    "coredns",
    "aws-ebs-csi-driver",
    "metrics-server",
  ])
}

data "aws_eks_addon_version" "this" {
  for_each = local.addon_names

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

# -----------------------------------------------------------------
# ROLE IRSA DO DRIVER EBS CSI
# -----------------------------------------------------------------
# Quem cria os volumes EBS dos PersistentVolumeClaims é o controlador do
# aws-ebs-csi-driver. Ele recebe permissão por IRSA, amarrada à
# ServiceAccount dele, e não pela role dos nós: assim um Pod qualquer
# não consegue criar ou apagar discos da conta.
# -----------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    sid = "EbsCsiControllerWebIdentity"
    # Troca do token OIDC da ServiceAccount por credencial temporária.
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    # Só a ServiceAccount do controlador, no kube-system, pode assumir.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    # O token precisa ter sido emitido para o STS.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name_prefix}-ebs-csi-irsa"
  description        = "IRSA do controlador aws-ebs-csi-driver do cluster ${var.cluster_name}: cria e anexa os volumes EBS dos PVCs."
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# -----------------------------------------------------------------
# OS ADDONS
# -----------------------------------------------------------------
# OVERWRITE na criação: o EKS instala versões autogerenciadas de vpc-cni,
# kube-proxy e coredns junto com o cluster, e o addon gerenciado assume o
# lugar delas. OVERWRITE na atualização: se o most_recent trouxer uma
# versão nova, a troca não para por conflito de configuração (nenhuma
# configuração destes addons é feita fora do Terraform).
# -----------------------------------------------------------------

# Rede dos Pods: sem ele, nenhum Pod recebe IP e os nós ficam NotReady.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.this["vpc-cni"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Regras de encaminhamento dos Services em cada nó.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.this["kube-proxy"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# DNS interno: resolve nomes como donation-service.solidarytech.svc.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.this["coredns"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # O CoreDNS roda em Pods: sem nós prontos, o addon fica DEGRADED e o
  # apply espera até estourar o tempo limite.
  depends_on = [aws_eks_node_group.this]
}

# Driver dos volumes EBS (PVCs). Sem ele, todo PVC fica Pending. As tags
# obrigatórias dos volumes vêm da StorageClass gp3 da raiz k8s.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Aqui a role IRSA é amarrada à ServiceAccount do controlador.
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # Nós prontos para os Pods do driver, e a policy já anexada à role
  # antes de o controlador tentar criar o primeiro volume.
  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

# Métricas de CPU e memória dos Pods. Sem ele, o HPA fica com alvo
# <unknown> e nunca escala, e o "kubectl top" não funciona.
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.this["metrics-server"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
