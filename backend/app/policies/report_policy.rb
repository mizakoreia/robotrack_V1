# frozen_string_literal: true

# commissioning-report 1.3 (§4.1, D3) — a policy de emissão do Protocolo.
#
# Emitir é LEITURA PURA: qualquer papel (inclusive `view`) emite (§4.1 inv. 4
# restringe MUTAÇÕES de `view`, e aqui nada muta). `read_workspace` cobre os três
# papéis. Não-membro → o gate levanta `NotFound` (papel nil) → 404, sem vazar nome
# nem contagens (D3.6/BasePolicy). Projeto de outro workspace é barrado pela RLS
# (find_by nil → 404), não por escopo no model (D2).
class ReportPolicy < BasePolicy
  permits show?: :read_workspace
end
