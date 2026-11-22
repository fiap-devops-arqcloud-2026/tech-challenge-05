# =================================================================
# SELF-HEALING — acesso da role do GitHub Actions ao cluster
# =================================================================
# A role do self-healing (raiz base) só pode DESCREVER o cluster na AWS
# (eks:DescribeCluster, para montar o kubeconfig). Para o kubectl dela
# funcionar, o EKS precisa saber quem ela é dentro do Kubernetes, e é
# isso que o access entry faz: "quando esta role chegar, trate-a como
# membro do grupo solidarytech-self-healing".
#
# O que esse grupo pode fazer é decidido pelo RBAC versionado no GitOps:
# um Role e um RoleBinding no namespace da aplicação, restritos a
# reiniciar os Deployments dela e acompanhar o resultado.
#
# POR QUE NÃO HÁ aws_eks_access_policy_association: as access policies
# prontas da AWS (AmazonEKSEditPolicy, por exemplo) liberam criar e
# apagar quase tudo no namespace. O self-healing precisa de muito menos,
# e só o RBAC próprio entrega exatamente isso.
#
# Funciona porque o cluster usa authentication_mode "API" (módulo eks):
# a autorização de quem entra vem só das access entries.
# =================================================================

locals {
  # Precisa ser idêntico, caractere por caractere, ao subject do
  # RoleBinding do GitOps. O EKS recusa grupos com prefixo "system:".
  self_healing_kubernetes_group = "solidarytech-self-healing"
}

resource "aws_eks_access_entry" "self_healing" {
  cluster_name = module.eks.cluster_name

  # ARN publicado pela raiz base (output self_healing_role_arn).
  principal_arn = local.self_healing_role_arn

  kubernetes_groups = [local.self_healing_kubernetes_group]

  # STANDARD é o tipo para roles e usuários IAM comuns; os demais tipos
  # são para nós do cluster e integrações da própria AWS.
  type = "STANDARD"
}
