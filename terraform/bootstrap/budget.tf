# =================================================================
# AWS BUDGET — alerta de gasto do projeto
# =================================================================
# Teto mensal com alertas por e-mail, filtrado pela tag Project. Nasce no
# bootstrap, e não junto com o cluster, para sobreviver aos destroys de
# cada janela de uso: o alerta precisa existir justamente enquanto o
# ambiente está ligado e gastando.
#
# Na Fase 4 o Budget foi criado pela CLI, fora do código. Aqui ele é
# código. O Budget antigo da Fase 4 continua na conta e não é tocado.
# =================================================================

locals {
  # Quatro alertas: três sobre o gasto REAL e um sobre a PREVISÃO do mês.
  # O previsto avisa no meio do mês que o teto vai estourar, ainda a
  # tempo de desligar o ambiente; o real a 100% confirma que estourou.
  budget_notifications = [
    { type = "ACTUAL", threshold = 50 },
    { type = "ACTUAL", threshold = 80 },
    { type = "ACTUAL", threshold = 100 },
    { type = "FORECASTED", threshold = 100 },
  ]
}

resource "aws_budgets_budget" "monthly" {
  name        = "${var.project_name}-mensal"
  budget_type = "COST"
  time_unit   = "MONTHLY"

  # O provider espera o valor como texto.
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"

  # Só conta o que tem a tag Project=SolidaryTech. "user:" é o prefixo das
  # tags definidas pelo cliente, e "$" separa chave e valor no formato da
  # API do Budgets. format() evita escrever o valor da tag duas vezes.
  #
  # LIMITAÇÃO CONHECIDA: o filtro só enxerga a tag depois que ela é
  # ATIVADA como tag de alocação de custo (cost-allocation-tags.tf). Até
  # lá, o Budget mostra US$ 0 mesmo com o ambiente ligado.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", local.required_tags.Project)]
  }

  # PEGADINHA DE CONTA COM CRÉDITOS: por padrão o Budget desconta créditos
  # e reembolsos. Numa conta paga por créditos promocionais, o custo
  # líquido fica perto de zero e o alerta NUNCA dispara. Com os dois em
  # false, o Budget mede o custo bruto, que é o que consome o crédito.
  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = local.budget_notifications

    content {
      notification_type   = notification.value.type
      comparison_operator = "GREATER_THAN"
      threshold           = notification.value.threshold
      threshold_type      = "PERCENTAGE"

      # Vem do tfvars local (sensitive): não aparece no plan nem no Git.
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
