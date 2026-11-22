# =================================================================
# TESTE DO MÓDULO EKS — regras que não podem regredir
# =================================================================
# Prova, sem tocar na AWS, as decisões do cluster que já custaram caro
# ou que quebram o projeto em silêncio se alguém as "melhorar":
#
#   1. o launch template NÃO define security groups (senão o EKS tira o
#      security group do cluster dos nós e o RDS fica inalcançável);
#   2. IMDSv2 obrigatório, com limite de saltos 2;
#   3. as tags obrigatórias chegam às instâncias e aos volumes dos nós;
#   4. disco raiz gp3 cifrado;
#   5. acesso só por access entries (API), suporte STANDARD, endpoint
#      público e privado, sem proteção contra exclusão;
#   6. os cinco addons, com a versão resolvida pelo data source, e o
#      EBS CSI com a sua role IRSA;
#   7. entradas inválidas são recusadas no plano.
#
# COMO RODA SEM AWS
# mock_provider troca o provider AWS por um falso: nada é chamado na AWS
# e os atributos calculados (ARNs, IDs, versões) recebem valores
# fictícios. Os runs usam command = apply, que no provider falso só
# simula a criação e deixa todos os valores conhecidos para as
# asserções. O cluster recebe valores fixos para o emissor OIDC, o
# endpoint e o certificado, que o provider falso não saberia montar.
#
# O provider falso ainda aplica as validações do provider real: um JSON
# de policy ou um ARN inventados ao acaso seriam recusados. Por isso os
# documentos de policy recebem um JSON mínimo válido e cada role, um ARN
# próprio (distintos entre si, para que a asserção do EBS CSI consiga
# diferenciar a role dele da role dos nós). O conteúdo das trusts IRSA é
# provado no teste do módulo irsa, com o JSON real.
#
# COMO RODAR
#   terraform -chdir=terraform/modules/eks init -backend=false
#   terraform -chdir=terraform/modules/eks test
# =================================================================

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}]}"
    }
  }

  # Versões no formato dos addons do EKS (o provider exige semver).
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }

  override_resource {
    target = aws_launch_template.node
    values = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  override_resource {
    target = aws_eks_cluster.this
    values = {
      arn      = "arn:aws:eks:us-east-2:000000000000:cluster/solidarytech-eks"
      endpoint = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-east-2.eks.amazonaws.com"
      certificate_authority = [
        { data = "Q0VSVElGSUNBRE8tRklDVElDSU8=" },
      ]
      identity = [
        {
          oidc = [
            { issuer = "https://oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" },
          ]
        },
      ]
    }
  }

  override_resource {
    target = aws_iam_role.cluster
    values = {
      arn = "arn:aws:iam::000000000000:role/solidarytech-eks-cluster-role"
    }
  }

  override_resource {
    target = aws_iam_role.node
    values = {
      arn = "arn:aws:iam::000000000000:role/solidarytech-eks-node-role"
    }
  }

  override_resource {
    target = aws_iam_role.ebs_csi
    values = {
      arn = "arn:aws:iam::000000000000:role/solidarytech-ebs-csi-irsa"
    }
  }

  override_resource {
    target = aws_iam_openid_connect_provider.cluster
    values = {
      arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

# Valores do projeto, como a raiz cluster os passa.
variables {
  cluster_name                 = "solidarytech-eks"
  name_prefix                  = "solidarytech"
  kubernetes_version           = "1.37"
  subnet_ids                   = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  endpoint_public_access_cidrs = ["0.0.0.0/0"]
  node_group_name              = "solidarytech-nodes"
  node_instance_type           = "m7i-flex.large"
  node_desired_size            = 2
  node_min_size                = 2
  node_max_size                = 3
  node_disk_size_gb            = 20
  node_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------
# 1 a 4. Launch template dos nós
# -----------------------------------------------------------------

run "launch_template_dos_nos" {
  command = apply

  assert {
    condition     = aws_launch_template.node.vpc_security_group_ids == null && aws_launch_template.node.security_group_names == null && length(aws_launch_template.node.network_interfaces) == 0
    error_message = "O launch template não pode definir security groups nem interfaces de rede: o EKS deixaria de anexar o security group do cluster aos nós, e o RDS ficaria inalcançável."
  }

  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_tokens == "required" && aws_launch_template.node.metadata_options[0].http_endpoint == "enabled"
    error_message = "O IMDSv2 deve ser obrigatório (http_tokens = required)."
  }

  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_put_response_hop_limit == 2
    error_message = "O limite de saltos do IMDS deve ser 2, o padrão do EKS (1 corta o acesso de Pods sem hostNetwork)."
  }

  assert {
    condition     = toset([for spec in aws_launch_template.node.tag_specifications : spec.resource_type]) == toset(["instance", "volume"])
    error_message = "O launch template deve marcar as instâncias e os volumes dos nós."
  }

  assert {
    condition = alltrue([
      for spec in aws_launch_template.node.tag_specifications :
      spec.tags["Project"] == "SolidaryTech" && spec.tags["Environment"] == "Production" && spec.tags["CostCenter"] == "NGO-Core" && spec.tags["Name"] == "solidarytech-nodes"
    ])
    error_message = "Instâncias e volumes dos nós devem levar as tags obrigatórias (Project, Environment, CostCenter) e o Name do node group."
  }

  assert {
    condition     = aws_launch_template.node.block_device_mappings[0].device_name == "/dev/xvda" && aws_launch_template.node.block_device_mappings[0].ebs[0].volume_type == "gp3" && aws_launch_template.node.block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.node.block_device_mappings[0].ebs[0].volume_size == 20
    error_message = "O disco raiz dos nós deve ser o /dev/xvda, gp3, cifrado e do tamanho pedido."
  }

  assert {
    condition     = aws_launch_template.node.image_id == null && aws_launch_template.node.instance_type == null && aws_launch_template.node.user_data == null && length(aws_launch_template.node.iam_instance_profile) == 0
    error_message = "AMI, tipo, user_data e perfil de instância ficam com o EKS e o node group, fora do launch template."
  }
}

# -----------------------------------------------------------------
# Node group
# -----------------------------------------------------------------

run "node_group_gerenciado" {
  command = apply

  assert {
    # tolist: no HCL, uma lista e uma tupla com os mesmos itens não são
    # iguais para o operador ==.
    condition     = aws_eks_node_group.this.ami_type == "AL2023_x86_64_STANDARD" && aws_eks_node_group.this.capacity_type == "ON_DEMAND" && aws_eks_node_group.this.instance_types == tolist(["m7i-flex.large"])
    error_message = "O node group deve usar AL2023 x86_64, ON_DEMAND e o tipo pedido."
  }

  assert {
    condition     = aws_eks_node_group.this.launch_template[0].id == aws_launch_template.node.id && aws_eks_node_group.this.launch_template[0].version == tostring(aws_launch_template.node.latest_version)
    error_message = "O node group deve usar a versão mais recente do launch template do módulo."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2 && aws_eks_node_group.this.scaling_config[0].min_size == 2 && aws_eks_node_group.this.scaling_config[0].max_size == 3
    error_message = "O node group deve seguir os tamanhos pedidos."
  }

  assert {
    condition     = aws_eks_node_group.this.node_group_name == "solidarytech-nodes" && aws_eks_node_group.this.version == "1.37"
    error_message = "O node group deve ter o nome pedido e a mesma versão do control plane."
  }
}

# -----------------------------------------------------------------
# 5. Cluster
# -----------------------------------------------------------------

run "cluster_e_acesso" {
  command = apply

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    error_message = "O acesso ao cluster deve ser só por access entries (API), com administrador para quem cria o cluster."
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "O cluster deve ficar no suporte STANDARD, sem a cobrança do suporte estendido."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true && aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["0.0.0.0/0"])
    error_message = "O endpoint deve ser público (com os CIDRs pedidos) e privado."
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == false && aws_eks_cluster.this.enabled_cluster_log_types == null && aws_eks_cluster.this.version == "1.37"
    error_message = "O cluster efêmero não deve ter proteção contra exclusão nem logs pagos do control plane, e deve usar a versão pedida."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.cluster.url == "https://oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF" && aws_iam_openid_connect_provider.cluster.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "O provedor OIDC do IRSA deve usar o emissor do cluster e o público sts.amazonaws.com."
  }

  assert {
    condition     = output.oidc_provider_url == "oidc.eks.us-east-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
    error_message = "A saída oidc_provider_url deve vir sem o prefixo https://, como pedem as chaves de condição do IRSA."
  }

  assert {
    condition     = aws_iam_role.cluster.name == "solidarytech-eks-cluster-role" && aws_iam_role.node.name == "solidarytech-eks-node-role" && aws_iam_role.ebs_csi.name == "solidarytech-ebs-csi-irsa"
    error_message = "As roles devem ter sufixo -role ou -irsa, para não serem confundidas com o nome do cluster."
  }
}

# -----------------------------------------------------------------
# 6. Addons
# -----------------------------------------------------------------

run "addons_gerenciados" {
  command = apply

  assert {
    condition     = toset([aws_eks_addon.vpc_cni.addon_name, aws_eks_addon.kube_proxy.addon_name, aws_eks_addon.coredns.addon_name, aws_eks_addon.ebs_csi.addon_name, aws_eks_addon.metrics_server.addon_name]) == toset(["vpc-cni", "kube-proxy", "coredns", "aws-ebs-csi-driver", "metrics-server"])
    error_message = "Os cinco addons gerenciados devem existir."
  }

  assert {
    condition     = aws_eks_addon.coredns.addon_version == data.aws_eks_addon_version.this["coredns"].version && aws_eks_addon.ebs_csi.addon_version == data.aws_eks_addon_version.this["aws-ebs-csi-driver"].version && aws_eks_addon.vpc_cni.addon_version == data.aws_eks_addon_version.this["vpc-cni"].version
    error_message = "A versão de cada addon deve vir do data source aws_eks_addon_version."
  }

  assert {
    condition     = data.aws_eks_addon_version.this["metrics-server"].most_recent == true && data.aws_eks_addon_version.this["metrics-server"].kubernetes_version == "1.37"
    error_message = "A versão dos addons deve ser a mais recente compatível com a versão do cluster."
  }

  assert {
    condition     = aws_eks_addon.ebs_csi.service_account_role_arn == aws_iam_role.ebs_csi.arn
    error_message = "O driver EBS CSI deve usar a própria role IRSA, e não a role dos nós."
  }
}

# -----------------------------------------------------------------
# 7. Entradas inválidas
# -----------------------------------------------------------------

run "tags_obrigatorias_sao_exigidas" {
  command = plan

  variables {
    node_tags = {
      Project     = "SolidaryTech"
      Environment = "Production"
    }
  }

  expect_failures = [var.node_tags]
}

run "tamanhos_inconsistentes_sao_recusados" {
  command = plan

  variables {
    node_desired_size = 4
    node_max_size     = 3
  }

  expect_failures = [var.node_max_size]
}

run "disco_menor_que_a_ami_e_recusado" {
  command = plan

  variables {
    node_disk_size_gb = 10
  }

  expect_failures = [var.node_disk_size_gb]
}
