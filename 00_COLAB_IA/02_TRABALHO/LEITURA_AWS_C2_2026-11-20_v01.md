# Leitura da conta AWS para a C2

TL;DR: Conta da Fase 4 (final 6140) limpa e pronta. Provedor OIDC do GitHub existente (importar), nenhum bucket, nenhum recurso cobrado em us-east-2 e us-east-1, cota de 16 vCPU nas duas regiões, US$ 126,41 de crédito. EKS 1.37 é a versão padrão, com suporte padrão até 2027-11-30.

Última atualização: 2026-11-20, Claude.

Somente leitura (`describe`, `list`, `get`), com o perfil `default` da AWS CLI (o único configurado), em 2026-11-20 por volta das 22:10 (UTC-03:00). Nenhum recurso foi criado, alterado ou apagado. O JSON bruto ficou fora do repositório.

| Item | Resultado | Uso na C2 |
|---|---|---|
| Identidade | Conta final 6140; usuário IAM do grupo `FIAP-Adm`; região padrão do perfil us-east-2 | `allowed_account_ids` e quem aplica o Terraform |
| Provedor OIDC do GitHub | Existe (criado em 2026-10-28 na Fase 4); cliente `sts.amazonaws.com`; thumbprint `ab9d0263244dd0326eb67015705a667e79cfe998`; tag `fiap=fase4` | Importar no bootstrap (D-012) com o mesmo cliente e thumbprint, para o import não gerar diferença além das tags |
| Subject OIDC do repositório | `use_immutable_subject: true`; prefixo `repo:fiap-devops-arqcloud-2026@287716251/tech-challenge-05@1454212968` (API do GitHub) | Trust das roles do CI: `...:ref:refs/heads/main` |
| Versões do EKS (us-east-2) | 1.37 padrão (suporte padrão até 2027-11-30); 1.36 até 2027-08-01; 1.35 até 2027-03-26; 1.34 até 2026-12-01 | EKS 1.37 com `upgrade_policy` STANDARD |
| Cota de vCPU On-Demand Standard | 16 em us-east-2 e 16 em us-east-1 (era 5 na Fase 4) | 2 nós de 2 vCPU com folga |
| Plano | FREE, ACTIVE; US$ 126,41 de crédito; expira em 2027-04-20 | Budget de US$ 50/mês (D-008) |
| Tipos EC2 elegíveis ao plano gratuito | c7i-flex.large (2 vCPU/4 GiB), m7i-flex.large (2 vCPU/8 GiB), t3/t4g/t8i/t9g micro e small | Nós `m7i-flex.large`, como na Fase 4 |
| RDS PostgreSQL 17 | 17.7 a 17.11 disponíveis para `db.t4g.micro` e `db.t3.micro`; versão padrão do RDS é 18.3 | PostgreSQL 17 (D-016), `db.t4g.micro` (Graviton, mais barato) |
| Buckets S3 | Nenhum | Bucket de estado criado pelo bootstrap |
| Budgets | `togglemaster-creditos` (US$ 80, período CUSTOM, sem filtro), da Fase 4 | Mantido; o da Fase 5 é novo e filtrado por tag |
| Recursos em us-east-2 e us-east-1 | Nenhum EKS, RDS, snapshot manual, ECR, SQS, DynamoDB, NAT, EIP, EBS, VPC não padrão, load balancer ou EC2 | Ambiente começa do zero |
| Roles IAM relacionadas | Só as service-linked do EKS (`AWSServiceRoleForAmazonEKS`, `...Nodegroup`) | Sem conflito de nomes |
