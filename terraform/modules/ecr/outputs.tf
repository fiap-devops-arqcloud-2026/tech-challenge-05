# =================================================================
# MÓDULO ECR — saídas
# =================================================================
# É por aqui que o módulo devolve valores a quem o chamou: a raiz base os
# repassa ao CI, ao GitOps e à policy de push do módulo iam-ci.
# =================================================================

output "repository_urls" {
  description = "Mapa serviço → URL do repositório (<conta>.dkr.ecr.<região>.amazonaws.com/<projeto>/<serviço>). Usado no docker push do CI e no campo images do GitOps."
  value       = { for service, repo in aws_ecr_repository.this : service => repo.repository_url }
}

output "repository_arns" {
  description = "ARNs dos repositórios. Restringem a policy de push do CI a estes repositórios, em vez de liberar o ECR inteiro da conta."
  value       = [for repo in aws_ecr_repository.this : repo.arn]
}

output "repository_names" {
  description = "Mapa serviço → nome do repositório, útil em comandos da AWS CLI."
  value       = { for service, repo in aws_ecr_repository.this : service => repo.name }
}

output "registry" {
  description = "Host do registro (<conta>.dkr.ecr.<região>.amazonaws.com), usado no docker login do CI."
  # O host é a parte da URL antes da primeira barra. Ele sai da URL que a
  # própria AWS devolve, em vez de ser montado à mão, para não depender de
  # suposição sobre o formato. distinct() reduz as URLs a um único host
  # (todos os repositórios são do mesmo registro) e one() o devolve.
  value = one(distinct([for repo in aws_ecr_repository.this : split("/", repo.repository_url)[0]]))
}
