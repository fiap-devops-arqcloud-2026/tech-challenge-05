# =================================================================
# NÓS DO CLUSTER — role IAM, launch template e node group gerenciado
# =================================================================
# Node group gerenciado: a AWS cria o Auto Scaling group, escolhe a AMI
# (AL2023) e faz a troca dos nós nas atualizações. O launch template
# próprio é novo na Fase 5 e existe por três motivos:
#
#   1. tags de custo nas instâncias e nos volumes — o node group NÃO
#      propaga as próprias tags para o que o Auto Scaling cria, e sem
#      elas o maior custo da conta some do filtro por tag do Budget;
#   2. IMDSv2 obrigatório, que protege as credenciais da role do nó
#      contra requisições forjadas ao serviço de metadados (SSRF);
#   3. disco raiz gp3 cifrado, declarado no código em vez de depender do
#      padrão da AMI e da configuração da conta.
#
# REGRA QUE NÃO PODE SER QUEBRADA: o launch template não define security
# groups (nem vpc_security_group_ids, nem network_interfaces). Quando ele
# define, o EKS deixa de anexar o security group do cluster aos nós, e o
# RDS, que aceita a porta 5432 só desse grupo, fica inalcançável para os
# Pods. O teste do módulo (tests/eks.tftest.hcl) guarda esta regra.
# =================================================================

# -----------------------------------------------------------------
# ROLE DOS NÓS
# -----------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    sid     = "Ec2AssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      # Aqui é EC2, e não EKS: quem assume a role é a instância do nó.
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-role"
  description        = "Instancias EC2 do node group ${var.node_group_name} do cluster ${var.cluster_name}."
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# As três policies gerenciadas que o EKS documenta para os nós. As
# permissões dos serviços NÃO entram aqui: cada Pod que fala com a AWS usa
# a própria role IRSA (módulo irsa). Mas a role do nó continua alcançável
# por qualquer Pod (ver o limite de saltos do IMDS no launch template),
# por isso ela leva o mínimo.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    # Registrar o nó no cluster e receber trabalho.
    "AmazonEKSWorkerNodePolicy",
    # Plugin de rede da VPC (aws-node): atribuir IPs da VPC aos Pods.
    "AmazonEKS_CNI_Policy",
    # Baixar imagens do ECR: as dos serviços e as dos próprios addons. A
    # PullOnly é a que o guia atual do EKS indica para os nós: só o
    # necessário para baixar imagens, sem listar nem descrever
    # repositórios e imagens, como a ReadOnly usada na Fase 4 permitia.
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# -----------------------------------------------------------------
# LAUNCH TEMPLATE
# -----------------------------------------------------------------
# Sem image_id e sem user_data: a AMI vem do ami_type do node group, e o
# EKS gera a configuração de entrada do nó no cluster (nodeadm). Sem
# instance_type: o tipo fica no node group (os dois juntos são
# recusados pelo EKS). Sem iam_instance_profile: o EKS cria o perfil a
# partir da role dos nós.
# -----------------------------------------------------------------

resource "aws_launch_template" "node" {
  name        = "${var.node_group_name}-lt"
  description = "Nos do node group ${var.node_group_name}: disco gp3 cifrado, IMDSv2 obrigatorio e tags de custo."

  # Cada mudança gera uma versão nova; o node group usa a mais recente
  # (latest_version) e troca os nós de forma gradual.
  update_default_version = true

  block_device_mappings {
    # Dispositivo raiz da AMI AL2023. Com outro nome, a instância ganharia
    # um segundo disco, e o raiz ficaria com o tamanho e o tipo da AMI.
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.node_disk_size_gb
      # gp3 custa menos que gp2 por GiB e já entrega 3.000 IOPS e
      # 125 MiB/s de base, sem cobrança extra.
      volume_type = "gp3"
      # Cifrado com a chave gerenciada aws/ebs. Uma chave KMS própria
      # exigiria liberar o seu uso ao Auto Scaling, sem ganho aqui.
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 obrigatório: o serviço de metadados só responde a quem
    # obtém antes um token de sessão (PUT), o que barra o SSRF comum, que
    # só consegue disparar um GET, atrás das credenciais da role do nó.
    http_tokens = "required"
    # Limite 2, o padrão do EKS, que funcionou na Fase 4. Com limite 1,
    # a resposta não atravessa o salto extra da rede do contêiner e
    # Pods sem hostNetwork, como os de alguns addons, perdem o acesso
    # ao serviço de metadados. Os serviços da aplicação não dependem
    # dele: suas credenciais vêm do IRSA.
    #
    # CUSTO ACEITO DESTA ESCOLHA: com o limite 2, QUALQUER Pod do nó (os
    # serviços, o gerador de tráfego, o Job de schema) alcança o serviço
    # de metadados e pode obter a credencial da role do nó, mesmo tendo a
    # própria role IRSA. Essa role carrega a AmazonEKS_CNI_Policy (criar,
    # anexar e apagar interfaces de rede na conta) e o pull de qualquer
    # repositório ECR da conta. Endurecimento possível, fora do primeiro
    # apply por exigir teste de ordem: role IRSA própria para o aws-node
    # (service_account_role_arn do addon vpc-cni) e a CNI fora da role do
    # nó.
    http_put_response_hop_limit = 2
  }

  # Uma especificação por tipo de recurso criado com a instância. A tag
  # Name ajuda a achar os nós no console; as demais são as obrigatórias.
  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])

    content {
      resource_type = tag_specifications.value
      tags          = merge(var.node_tags, { Name = var.node_group_name })
    }
  }

  # Sem vpc_security_group_ids e sem network_interfaces: ver o cabeçalho
  # deste arquivo. É isso que mantém o security group do cluster nos nós.
}

# -----------------------------------------------------------------
# NODE GROUP
# -----------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # Mesma versão do control plane: numa atualização do Kubernetes, os nós
  # são trocados logo depois do control plane.
  version = aws_eks_cluster.this.version

  # Amazon Linux 2023 para x86_64, compatível com o m7i-flex.large.
  ami_type = "AL2023_x86_64_STANDARD"

  # ON_DEMAND e não SPOT: uma instância Spot pode ser retomada pela AWS a
  # qualquer momento, e perder um nó no meio de uma demonstração custa
  # mais do que a economia de uma janela de poucas horas.
  capacity_type  = "ON_DEMAND"
  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    # Numa troca de nós, no máximo um fica indisponível por vez.
    max_unavailable = 1
  }

  # Um nó sem as policies sobe, não consegue entrar no cluster e deixa o
  # node group em CREATE_FAILED depois de vários minutos.
  depends_on = [aws_iam_role_policy_attachment.node]
}
