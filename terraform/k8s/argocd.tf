# =================================================================
# ARGOCD — entrega contínua por GitOps
# =================================================================
# O ArgoCD observa a pasta do overlay no repositório e mantém o cluster
# igual a ela: é o que elimina o "kubectl apply" manual. O ciclo:
#   1. push na main -> o CI testa, escaneia e publica a imagem no ECR;
#   2. o CI grava a nova tag da imagem no overlay e faz commit;
#   3. o ArgoCD detecta o commit e aplica a diferença no cluster.
# Este arquivo é o passo 3; os passos 1 e 2 ficam nos workflows.
#
# Duas releases Helm, uma depois da outra, num único apply:
#   - argo-cd:     instala o ArgoCD e as CRDs (Application, AppProject,
#                  ApplicationSet);
#   - argocd-apps: cria a Application do projeto, só com
#                  enable_applications = true.
#
# POR QUE O CHART argocd-apps, E NÃO kubernetes_manifest (Fase 4)
# O kubernetes_manifest valida o objeto contra a CRD ainda no PLAN. Num
# cluster novo a CRD Application não existe no plan (ela nasce no apply,
# com o chart do ArgoCD), e o plan morria com "no matches for kind
# Application". A Fase 4 precisava de dois applies, o primeiro com
# -target. Uma helm_release não consulta a CRD no plan: com depends_on, a
# Application é instalada depois do ArgoCD, no mesmo apply.
# =================================================================

locals {
  # Separado do namespace da aplicação: o ArgoCD é infraestrutura do
  # cluster, com ciclo de vida próprio. "argocd" é o nome que a
  # documentação do Argo CD e os comandos de acesso (README) assumem.
  argocd_namespace = "argocd"

  # Repositório oficial de charts do projeto Argo.
  argo_helm_repository = "https://argoproj.github.io/argo-helm"
}

# -----------------------------------------------------------------
# INSTALAÇÃO DO ARGOCD
# -----------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = local.argo_helm_repository
  chart      = "argo-cd"

  # Versão fixa (ver a descrição da variável).
  version = var.argocd_chart_version

  namespace = local.argocd_namespace

  # O Helm cria o namespace. No destroy, o uninstall NÃO apaga o
  # namespace (comportamento do Helm); como o cluster inteiro é destruído
  # em seguida, isso não deixa sobra cobrada.
  create_namespace = true

  # Só conclui quando os Pods do ArgoCD estão prontos. Sem isto, a
  # Application seria enviada a um ArgoCD ainda subindo.
  wait = true

  # 10 minutos: num cluster novo, baixar as imagens e subir controller,
  # repo-server, server e redis leva alguns minutos.
  timeout = 600

  # Valores por yamlencode, e não por "set": chaves com ponto no nome
  # (como "server.insecure") viram só uma chave entre aspas, sem o escape
  # frágil com barra invertida que o "set" exige (tropeço da Fase 4).
  values = [yamlencode({
    configs = {
      params = {
        # Servidor em HTTP dentro do cluster. Não há Ingress nem Load
        # Balancer (custo e superfície de ataque): o acesso é por
        # "kubectl port-forward", que já trafega cifrado pelo túnel da API
        # do Kubernetes. Com TLS próprio, o navegador exigiria aceitar um
        # certificado autoassinado.
        "server.insecure" = true
      }

      cm = {
        # O padrão do chart é consultar o Git a cada 120 s, mais até 60 s
        # de variação aleatória (jitter). Para a demonstração do GitOps, o
        # ArgoCD precisa perceber o commit enquanto a câmera está ligada:
        # 30 s, sem variação. Com UMA Application e um repositório
        # pequeno, o custo extra de consultas é irrelevante. Webhook seria
        # instantâneo, mas exigiria expor o ArgoCD à internet.
        "timeout.reconciliation"        = "30s"
        "timeout.reconciliation.jitter" = "0s"
      }
    }

    # Componentes desligados: cada um é um Pod a mais consumindo CPU e
    # memória de um cluster de dois nós, sem uso no projeto.
    #   Dex: login federado (o acesso é pelo usuário admin local);
    dex = {
      enabled = false
    }
    #   notifications: avisos do ArgoCD (alertas saem da observabilidade);
    notifications = {
      enabled = false
    }
    #   applicationSet: gera Applications em massa (o projeto tem uma).
    #   Nesta linha do chart NÃO existe applicationSet.enabled: o
    #   Deployment é sempre renderizado, e uma chave "enabled" seria
    #   ignorada em silêncio. Zero réplicas é o que de fato desliga.
    applicationSet = {
      replicas = 0
    }

    # Uma réplica de cada componente e recursos pequenos. Os requests são
    # o que o agendador reserva nos nós; os limites contêm um vazamento
    # de memória sem derrubar o nó inteiro.
    controller = {
      replicas = 1
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "768Mi" }
      }
    }

    server = {
      replicas = 1

      # Sem IP externo: acesso só por port-forward.
      service = {
        type = "ClusterIP"
      }

      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }

    # O repo-server renderiza o Kustomize a cada sincronização: é o que
    # mais varia de CPU, por isso o limite maior.
    repoServer = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    redis = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }
  })]
}

# -----------------------------------------------------------------
# APPLICATION DO PROJETO
# -----------------------------------------------------------------
# Só existe com enable_applications = true: a Application aponta para uma
# pasta do repositório, que precisa existir na branch observada, e para
# imagens que o CI precisa ter publicado. Antes disso, ela nasceria com
# erro de sincronização.
# -----------------------------------------------------------------
resource "helm_release" "argocd_apps" {
  count = var.enable_applications ? 1 : 0

  name       = "argocd-apps"
  repository = local.argo_helm_repository
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = helm_release.argocd.namespace

  # Na instalação, a Application é aceita na hora. No DESTROY, o wait faz
  # o Terraform esperar o ArgoCD terminar a limpeza descrita no
  # finalizer abaixo, antes de desinstalar o próprio ArgoCD.
  wait    = true
  timeout = 600

  values = [yamlencode({
    # Na linha 2.x do chart, "applications" é um mapa: a chave é o nome da
    # Application exibida na interface do ArgoCD.
    applications = {
      (var.project_name) = {
        # A Application mora no namespace do ArgoCD, não no da aplicação.
        namespace = helm_release.argocd.namespace

        # PEGADINHA DA FASE 4 (discos órfãos): sem este finalizer, apagar
        # a Application deixa no cluster tudo o que ela criou; o cluster é
        # destruído depois e os volumes EBS sobram, cobrando. Com ele, o
        # ArgoCD apaga primeiro os recursos que a Application gerencia (os
        # declarados no Git, inclusive PVCs declarados lá) e só então a
        # remove.
        #
        # LIMITE: um PVC criado pelo volumeClaimTemplates de um StatefulSet
        # não é recurso da Application. O Kubernetes o mantém quando o
        # StatefulSet sai (retenção padrão whenDeleted: Retain), e ele só
        # some junto com o namespace. Ver "Destruir" no README.md.
        finalizers = ["resources-finalizer.argocd.argoproj.io"]

        # Projeto padrão criado pelo chart do ArgoCD.
        project = "default"

        # ONDE ESTÁ A VERDADE: o overlay Kustomize no repositório.
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_app_path
        }

        # ONDE APLICAR: o próprio cluster em que o ArgoCD roda, no
        # namespace da aplicação. A referência ao recurso também garante
        # que, no destroy, a Application sai antes do namespace.
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = kubernetes_namespace_v1.app.metadata[0].name
        }

        syncPolicy = {
          automated = {
            # prune: o que sai do Git sai do cluster. Sem isso, um recurso
            # apagado do repositório continuaria vivo para sempre.
            prune = true

            # selfHeal: desfaz mudança feita à mão no cluster ("kubectl
            # edit"). É o que mantém o Git como fonte da verdade.
            selfHeal = true
          }

          # Falhas temporárias (imagem ainda sendo publicada, API ocupada)
          # são tentadas de novo: 5 s, 10 s, 20 s... até 3 minutos.
          retry = {
            limit = 5
            backoff = {
              duration    = "5s"
              factor      = 2
              maxDuration = "3m"
            }
          }
        }

        # Se algum Deployment ganhar HPA, acrescentar aqui ignoreDifferences
        # em /spec/replicas desse Deployment e, em syncPolicy,
        # syncOptions = ["RespectIgnoreDifferences=true"]: sem isso,
        # selfHeal e HPA disputam o número de réplicas, como na Fase 4.
      }
    }
  })]

  # A CRD Application vem com o chart do ArgoCD. Os objetos que os Pods
  # usam (Secrets, ConfigMap, ServiceAccounts e a StorageClass padrão)
  # vêm antes da primeira sincronização, para os Pods não subirem em
  # CreateContainerConfigError. No destroy, a ordem se inverte: a
  # Application sai primeiro.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.ngo_db,
    kubernetes_secret_v1.donation_db,
    kubernetes_secret_v1.db_schema,
    kubernetes_config_map_v1.aws,
    kubernetes_service_account_v1.irsa,
    kubernetes_service_account_v1.ngo,
    kubernetes_storage_class_v1.gp3,
  ]
}
