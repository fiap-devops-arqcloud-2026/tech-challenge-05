# =================================================================
# TAGS DE ALOCAÇÃO DE CUSTO
# =================================================================
# Uma tag só aparece no Cost Explorer, no relatório de custos e no filtro
# do Budget depois de ATIVADA como tag de alocação de custo. Sem isso, as
# tags existem nos recursos, mas o faturamento não as enxerga.
#
# POR QUE COMEÇA DESLIGADO (activate_cost_allocation_tags = false)
# A AWS só aceita ativar uma chave que já apareceu no faturamento, o que
# acontece até 24 h depois de o primeiro recurso com a tag existir. No
# primeiro apply do bootstrap nenhum recurso tagueado tem esse tempo, e a
# ativação falharia. O passo é feito depois, com a infraestrutura de pé:
# trocar a variável para true e aplicar de novo.
#
# Até a ativação, o filtro por tag do Budget fica sem dados (US$ 0).
# =================================================================

locals {
  # ManagedBy fica de fora: identifica a origem do recurso, não é eixo de
  # rateio de custo.
  cost_allocation_tag_keys = ["Project", "Environment", "CostCenter"]
}

resource "aws_ce_cost_allocation_tag" "required" {
  # Conjunto vazio quando desligado: nenhuma instância é planejada.
  for_each = var.activate_cost_allocation_tags ? toset(local.cost_allocation_tag_keys) : toset([])

  tag_key = each.value
  status  = "Active"
}
