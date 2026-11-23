# =================================================================
# TESTES DA RAIZ K8S — sem AWS, sem cluster, sem custo
# =================================================================
# Provam o contrato desta raiz com o GitOps e com as outras raízes:
#   1. namespace e StorageClass gp3 padrão, com as tags do FinOps nos
#      volumes EBS;
#   2. Secrets dos bancos com os nomes, as chaves e o formato de URL que
#      os serviços e o Job de schema esperam, e a mesma senha de
#      aplicação nos dois lados;
#   3. ConfigMap e ServiceAccounts (IRSA só onde há acesso à AWS);
#   4. ArgoCD enxuto e a Application só com enable_applications = true;
#   5. entradas inconsistentes recusadas no plan.
#
# COMO RODA SEM NADA REAL
# Os providers aws, kubernetes e helm são simulados (mock_provider): nada
# sai da máquina. Os estados das raízes base e cluster são substituídos
# por valores fictícios (override_data), com os mesmos nomes de outputs
# do contrato. O provider random é o real: gera as senhas localmente,
# o que permite conferir tamanho e alfabeto.
#
# COMO RODAR
#   terraform -chdir=terraform/k8s init -backend=false
#   terraform -chdir=terraform/k8s test
# =================================================================

mock_provider "aws" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}

# Outputs fictícios da raiz base (nomes exatos do contrato).
override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      aws_region          = "us-east-2"
      sqs_queue_url       = "https://sqs.us-east-2.amazonaws.com/000000000000/solidary-donations"
      dynamodb_table_name = "SolidaryTechVolunteers"
    }
  }
}

# Outputs fictícios da raiz cluster (nomes exatos do contrato). O
# certificado é só um base64 válido, para o base64decode dos providers.
override_data {
  target = data.terraform_remote_state.cluster
  values = {
    outputs = {
      cluster_name                       = "solidarytech-eks"
      cluster_endpoint                   = "https://exemplo.gr7.us-east-2.eks.amazonaws.com"
      cluster_certificate_authority_data = "dGVzdGUtb2ZmbGluZQ=="
      rds_address                        = "solidarytech-postgres.exemplo.us-east-2.rds.amazonaws.com"
      rds_port                           = 5432
      rds_master_username                = "solidary_admin"
      rds_master_password                = "senha-mestre-ficticia"
      irsa_role_arns = {
        "donation-service"  = "arn:aws:iam::000000000000:role/solidarytech-donation-service-irsa"
        "volunteer-service" = "arn:aws:iam::000000000000:role/solidarytech-volunteer-service-irsa"
      }
      app_namespace = "solidarytech"
    }
  }
}

variables {
  expected_aws_account_id = "000000000000"
  state_bucket            = "solidarytech-tfstate-000000000000-us-east-2-an"
  state_region            = "us-east-2"
}

# -----------------------------------------------------------------
# 1. Namespace e StorageClass
# -----------------------------------------------------------------

run "namespace_e_storageclass_padrao" {
  command = apply

  assert {
    condition     = kubernetes_namespace_v1.app.metadata[0].name == "solidarytech" && output.app_namespace == "solidarytech"
    error_message = "O namespace da aplicação deve vir do output app_namespace da raiz cluster."
  }

  assert {
    condition     = kubernetes_namespace_v1.app.metadata[0].labels["app.kubernetes.io/part-of"] == "solidarytech"
    error_message = "O namespace deve ter o rótulo app.kubernetes.io/part-of = solidarytech."
  }

  assert {
    condition     = kubernetes_storage_class_v1.gp3.metadata[0].annotations["storageclass.kubernetes.io/is-default-class"] == "true"
    error_message = "A StorageClass gp3 deve ser a padrão do cluster."
  }

  assert {
    condition = (
      kubernetes_storage_class_v1.gp3.storage_provisioner == "ebs.csi.aws.com" &&
      kubernetes_storage_class_v1.gp3.volume_binding_mode == "WaitForFirstConsumer" &&
      kubernetes_storage_class_v1.gp3.reclaim_policy == "Delete" &&
      kubernetes_storage_class_v1.gp3.allow_volume_expansion == true
    )
    error_message = "A StorageClass deve usar o EBS CSI, esperar o Pod (WaitForFirstConsumer), apagar o disco com o PVC e permitir expansão."
  }

  assert {
    condition     = kubernetes_storage_class_v1.gp3.parameters["type"] == "gp3" && kubernetes_storage_class_v1.gp3.parameters["encrypted"] == "true"
    error_message = "Os volumes devem ser gp3 e cifrados."
  }

  assert {
    condition = toset([
      for k, v in kubernetes_storage_class_v1.gp3.parameters : v if startswith(k, "tagSpecification_")
      ]) == toset([
      "Project=SolidaryTech",
      "Environment=Production",
      "CostCenter=NGO-Core",
      "ManagedBy=Terraform",
    ])
    error_message = "Os volumes EBS do CSI devem receber as quatro tags obrigatórias por tagSpecification_N."
  }
}

# -----------------------------------------------------------------
# 2. Secrets dos bancos
# -----------------------------------------------------------------

run "secrets_dos_bancos" {
  command = apply

  assert {
    condition     = kubernetes_secret_v1.ngo_db.metadata[0].name == "ngo-service-db" && kubernetes_secret_v1.ngo_db.metadata[0].namespace == "solidarytech"
    error_message = "O Secret do ngo-service deve se chamar ngo-service-db, no namespace da aplicação."
  }

  assert {
    condition     = can(regex("^postgresql://ngo_app:[A-Za-z0-9]{24}@solidarytech-postgres\\.exemplo\\.us-east-2\\.rds\\.amazonaws\\.com:5432/ngo_db\\?sslmode=require$", nonsensitive(kubernetes_secret_v1.ngo_db.data["DATABASE_URL"])))
    error_message = "DATABASE_URL do ngo-service deve ser postgresql://ngo_app:<24 alfanuméricos>@<rds>:<porta>/ngo_db?sslmode=require."
  }

  assert {
    condition     = kubernetes_secret_v1.donation_db.metadata[0].name == "donation-service-db" && kubernetes_secret_v1.donation_db.metadata[0].namespace == "solidarytech"
    error_message = "O Secret do donation-service deve se chamar donation-service-db, no namespace da aplicação."
  }

  assert {
    condition     = can(regex("^postgres://donation_app:[A-Za-z0-9]{24}@solidarytech-postgres\\.exemplo\\.us-east-2\\.rds\\.amazonaws\\.com:5432/donation_db\\?sslmode=require$", nonsensitive(kubernetes_secret_v1.donation_db.data["DATABASE_URL"])))
    error_message = "DATABASE_URL do donation-service deve ser postgres://donation_app:<24 alfanuméricos>@<rds>:<porta>/donation_db?sslmode=require."
  }

  assert {
    condition = toset(keys(kubernetes_secret_v1.db_schema.data)) == toset([
      "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGSSLMODE", "NGO_APP_PASSWORD", "DONATION_APP_PASSWORD",
    ])
    error_message = "O Secret db-schema deve ter exatamente as chaves do contrato com o Job de schema."
  }

  assert {
    condition = nonsensitive(
      kubernetes_secret_v1.db_schema.data["PGHOST"] == "solidarytech-postgres.exemplo.us-east-2.rds.amazonaws.com" &&
      kubernetes_secret_v1.db_schema.data["PGPORT"] == "5432" &&
      kubernetes_secret_v1.db_schema.data["PGUSER"] == "solidary_admin" &&
      kubernetes_secret_v1.db_schema.data["PGPASSWORD"] == "senha-mestre-ficticia" &&
      kubernetes_secret_v1.db_schema.data["PGSSLMODE"] == "require"
    )
    error_message = "O Secret db-schema deve levar endereço, porta e credencial mestre do RDS vindos do estado do cluster, com TLS obrigatório."
  }

  # A senha que o Job grava no banco precisa ser a mesma que o serviço usa
  # para conectar; divergência só apareceria em execução.
  assert {
    condition = nonsensitive(
      strcontains(kubernetes_secret_v1.ngo_db.data["DATABASE_URL"], ":${kubernetes_secret_v1.db_schema.data["NGO_APP_PASSWORD"]}@") &&
      strcontains(kubernetes_secret_v1.donation_db.data["DATABASE_URL"], ":${kubernetes_secret_v1.db_schema.data["DONATION_APP_PASSWORD"]}@")
    )
    error_message = "As senhas de aplicação do db-schema devem ser as mesmas dos DATABASE_URL dos serviços."
  }

  assert {
    condition     = nonsensitive(random_password.ngo_app.result != random_password.donation_app.result)
    error_message = "Cada serviço deve ter uma senha própria."
  }

  # O terraform_remote_state não preserva a marca sensitive dos outputs:
  # a raiz precisa remarcar a senha mestre por conta própria.
  assert {
    condition     = issensitive(local.rds_master_password)
    error_message = "A senha mestre lida do estado do cluster deve ser tratada como sensitive nesta raiz."
  }

  assert {
    condition = output.db_secret_names == {
      "ngo-service"      = "ngo-service-db"
      "donation-service" = "donation-service-db"
      "schema-job"       = "db-schema"
    }
    error_message = "O output db_secret_names deve mapear cada consumidor ao seu Secret."
  }
}

# -----------------------------------------------------------------
# 3. ConfigMap e ServiceAccounts
# -----------------------------------------------------------------

run "configmap_aws_endpoints" {
  command = apply

  assert {
    condition = kubernetes_config_map_v1.aws.data == tomap({
      AWS_REGION         = "us-east-2"
      AWS_SQS_URL        = "https://sqs.us-east-2.amazonaws.com/000000000000/solidary-donations"
      AWS_DYNAMODB_TABLE = "SolidaryTechVolunteers"
    })
    error_message = "O ConfigMap deve ter exatamente AWS_REGION, AWS_SQS_URL e AWS_DYNAMODB_TABLE, vindos da raiz base."
  }

  assert {
    condition     = kubernetes_config_map_v1.aws.metadata[0].name == "aws-endpoints" && output.aws_config_map_name == "aws-endpoints"
    error_message = "O ConfigMap deve se chamar aws-endpoints."
  }
}

run "serviceaccounts_com_irsa_so_onde_precisa" {
  command = apply

  assert {
    condition     = kubernetes_service_account_v1.irsa["donation-service"].metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::000000000000:role/solidarytech-donation-service-irsa"
    error_message = "A ServiceAccount donation-service deve apontar para a role IRSA dela."
  }

  assert {
    condition     = kubernetes_service_account_v1.irsa["volunteer-service"].metadata[0].annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::000000000000:role/solidarytech-volunteer-service-irsa"
    error_message = "A ServiceAccount volunteer-service deve apontar para a role IRSA dela."
  }

  assert {
    condition     = kubernetes_service_account_v1.ngo.metadata[0].name == "ngo-service" && length(coalesce(kubernetes_service_account_v1.ngo.metadata[0].annotations, {})) == 0
    error_message = "A ServiceAccount ngo-service não deve ter role IRSA."
  }

  assert {
    condition     = kubernetes_service_account_v1.ngo.automount_service_account_token == false
    error_message = "O ngo-service não deve montar o token da ServiceAccount."
  }
}

# -----------------------------------------------------------------
# 4. ArgoCD e Application
# -----------------------------------------------------------------

run "argocd_enxuto_sem_application_por_padrao" {
  command = apply

  assert {
    condition = (
      helm_release.argocd.chart == "argo-cd" &&
      helm_release.argocd.repository == "https://argoproj.github.io/argo-helm" &&
      helm_release.argocd.version == "10.18.2" &&
      helm_release.argocd.namespace == "argocd" &&
      helm_release.argocd.create_namespace == true &&
      output.argocd_namespace == "argocd"
    )
    error_message = "O ArgoCD deve vir do chart oficial argo-cd 10.18.2, no namespace argocd criado pelo Helm."
  }

  # O chart 10.x não tem applicationSet.enabled: o desligamento é por
  # zero réplicas (ver argocd.tf).
  assert {
    condition = (
      yamldecode(helm_release.argocd.values[0]).dex.enabled == false &&
      yamldecode(helm_release.argocd.values[0]).notifications.enabled == false &&
      yamldecode(helm_release.argocd.values[0]).applicationSet.replicas == 0
    )
    error_message = "Dex e notifications devem ficar desligados, e o ApplicationSet controller com zero réplicas."
  }

  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).configs.params["server.insecure"] == true
    error_message = "O servidor do ArgoCD deve servir HTTP interno (acesso só por port-forward)."
  }

  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).server.service.type == "ClusterIP"
    error_message = "O servidor do ArgoCD não deve ganhar IP externo (acesso por port-forward)."
  }

  assert {
    condition = alltrue([
      for c in ["controller", "server", "repoServer", "redis"] :
      can(yamldecode(helm_release.argocd.values[0])[c].resources.requests.memory) && can(yamldecode(helm_release.argocd.values[0])[c].resources.limits.memory)
    ])
    error_message = "Cada componente do ArgoCD deve declarar requests e limits."
  }

  assert {
    condition     = length(helm_release.argocd_apps) == 0
    error_message = "Sem enable_applications, a Application não deve ser criada."
  }
}

run "application_ligada" {
  command = apply

  variables {
    enable_applications = true
  }

  assert {
    condition = (
      length(helm_release.argocd_apps) == 1 &&
      helm_release.argocd_apps[0].chart == "argocd-apps" &&
      helm_release.argocd_apps[0].version == "2.0.8" &&
      helm_release.argocd_apps[0].namespace == "argocd"
    )
    error_message = "Com enable_applications, o chart argocd-apps 2.0.8 deve ser instalado no namespace do ArgoCD."
  }

  assert {
    condition = yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.source == {
      repoURL        = "https://github.com/fiap-devops-arqcloud-2026/tech-challenge-05.git"
      targetRevision = "main"
      path           = "gitops/overlays/prod"
    }
    error_message = "A Application deve observar gitops/overlays/prod na main do repositório do projeto."
  }

  assert {
    condition = yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.destination == {
      server    = "https://kubernetes.default.svc"
      namespace = "solidarytech"
    }
    error_message = "A Application deve aplicar no próprio cluster, no namespace da aplicação."
  }

  assert {
    condition = (
      yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.syncPolicy.automated.prune == true &&
      yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.syncPolicy.automated.selfHeal == true &&
      yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.syncPolicy.retry.limit > 0
    )
    error_message = "A sincronização deve ser automática, com prune, selfHeal e retry."
  }

  assert {
    condition     = contains(yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.finalizers, "resources-finalizer.argocd.argoproj.io")
    error_message = "A Application deve ter o finalizer que apaga os recursos dela (e os PVCs) antes de sair."
  }

  assert {
    condition     = yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.project == "default" && yamldecode(helm_release.argocd_apps[0].values[0]).applications.solidarytech.namespace == "argocd"
    error_message = "A Application deve usar o projeto default e morar no namespace do ArgoCD."
  }
}

# -----------------------------------------------------------------
# Tags obrigatórias (mesmo mapa nas quatro raízes)
# -----------------------------------------------------------------
# Aqui o mapa vai para o default_tags do provider AWS e para os
# tagSpecification_N da StorageClass, que marcam os discos dos PVCs.
run "tags_obrigatorias_do_contrato" {
  command = plan

  assert {
    condition = local.required_tags == {
      Project     = "SolidaryTech"
      Environment = "Production"
      CostCenter  = "NGO-Core"
      ManagedBy   = "Terraform"
    }
    error_message = "As tags obrigatórias devem ser exatamente Project=SolidaryTech, Environment=Production, CostCenter=NGO-Core e ManagedBy=Terraform."
  }
}

# -----------------------------------------------------------------
# 5. Entradas inconsistentes
# -----------------------------------------------------------------

run "recusa_regiao_diferente_da_base" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [kubernetes_namespace_v1.app]
}

run "recusa_cluster_sem_role_irsa" {
  command = plan

  override_data {
    target = data.terraform_remote_state.cluster
    values = {
      outputs = {
        cluster_name                       = "solidarytech-eks"
        cluster_endpoint                   = "https://exemplo.gr7.us-east-2.eks.amazonaws.com"
        cluster_certificate_authority_data = "dGVzdGUtb2ZmbGluZQ=="
        rds_address                        = "solidarytech-postgres.exemplo.us-east-2.rds.amazonaws.com"
        rds_port                           = 5432
        rds_master_username                = "solidary_admin"
        rds_master_password                = "senha-mestre-ficticia"
        irsa_role_arns = {
          "donation-service" = "arn:aws:iam::000000000000:role/solidarytech-donation-service-irsa"
        }
        app_namespace = "solidarytech"
      }
    }
  }

  expect_failures = [kubernetes_service_account_v1.irsa]
}

# O bucket de estado fica no namespace regional da conta: o nome termina
# em -<conta>-<região>-an, sufixo que só a própria conta consegue criar.
# Um bucket de outra conta é recusado antes de qualquer leitura de estado.
# O nome usa texto no lugar de outro ID de 12 dígitos, para que a
# varredura de IDs de conta só encontre a conta fictícia 000000000000.
run "recusa_bucket_de_estado_de_outra_conta" {
  command = plan

  variables {
    state_bucket = "solidarytech-tfstate-outra-conta-us-east-2-an"
  }

  expect_failures = [var.state_bucket]
}

# Com a conta certa, mas no namespace global (sem -an): qualquer conta
# poderia ter criado esse nome, então também é recusado.
run "recusa_bucket_de_estado_fora_do_namespace_da_conta" {
  command = plan

  variables {
    state_bucket = "solidarytech-tfstate-000000000000-us-east-2"
  }

  expect_failures = [var.state_bucket]
}

run "recusa_caminho_gitops_absoluto" {
  command = plan

  variables {
    gitops_app_path = "/gitops/overlays/prod"
  }

  expect_failures = [var.gitops_app_path]
}

run "recusa_versao_de_chart_em_aberto" {
  command = plan

  variables {
    argocd_chart_version = "10.*"
  }

  expect_failures = [var.argocd_chart_version]
}
