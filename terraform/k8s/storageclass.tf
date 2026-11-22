# =================================================================
# STORAGECLASS gp3 PADRÃO DO CLUSTER
# =================================================================
# Todo PersistentVolumeClaim (Prometheus, Loki e o que mais vier pelo
# GitOps) é atendido por uma StorageClass.
#
# PEGADINHA DA FASE 4: o EKS não marca nenhuma classe como padrão. Sem
# uma classe padrão e sem storageClassName no manifesto, o PVC fica em
# Pending para sempre e o Pod que depende dele nunca sobe.
#
# FINOPS: volumes criados dinamicamente pelo driver EBS CSI não herdam o
# default_tags do provider AWS (quem cria é o driver, não o Terraform).
# Sem as tags explícitas abaixo, esses discos ficariam fora do custo por
# tag do projeto. Na Fase 4 eles também sobraram órfãos depois do destroy
# e só foram achados procurando volumes "available" à mão.
# =================================================================

locals {
  # Parâmetros tagSpecification_N do driver EBS CSI, no formato
  # "Chave=Valor", gerados da mesma política de tags das outras raízes.
  # A ordem alfabética só deixa a numeração estável entre planos.
  ebs_tag_parameters = {
    for index, key in sort(keys(local.required_tags)) :
    "tagSpecification_${index + 1}" => "${key}=${local.required_tags[key]}"
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"

    annotations = {
      # É esta anotação que torna a classe padrão: PVC sem
      # storageClassName passa a usar esta.
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  # Driver instalado como addon gerenciado pela raiz cluster.
  storage_provisioner = "ebs.csi.aws.com"

  # O volume só nasce depois que o Pod é agendado. Um volume EBS vive numa
  # única zona de disponibilidade; com Immediate, ele poderia nascer em
  # us-east-2a e o Pod ir para um nó em us-east-2b, sem conseguir montar.
  volume_binding_mode = "WaitForFirstConsumer"

  # Apagou o PVC, o disco some junto. O ambiente é efêmero, e disco órfão
  # continuaria sendo cobrado sem ninguém ver.
  reclaim_policy = "Delete"

  # Permite aumentar o disco depois, sem recriar o volume.
  allow_volume_expansion = true

  parameters = merge(
    {
      # gp3 é mais barato que gp2 no mesmo tamanho e não amarra o
      # desempenho ao tamanho do disco.
      type = "gp3"

      # Cifragem em repouso com a chave padrão da conta para EBS.
      encrypted = "true"
    },
    local.ebs_tag_parameters,
  )
}
