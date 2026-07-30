# frozen_string_literal: true

# notification-preferences G6 (design §D-P8) — eventos estruturais.
#
# Acrescenta o valor COARSE `'structure'` ao enum `notification_type`. Um só
# valor: a ação (created/deleted) e a entidade (project/cell/robot/task) vão no
# TEXTO materializado da mensagem, não em granularidade de enum — o `type` só
# serve a idempotência, filtro e ícone, nenhum precisa distinguir a ação.
#
# 🔴 REVERSÃO NÃO-TRIVIAL: `ALTER TYPE ... ADD VALUE` não roda dentro de uma
# transação que já usa o valor, daí `disable_ddl_transaction!`. E o Postgres NÃO
# tem `DROP VALUE` — remover um valor de enum exige recriar o tipo e recompor
# todas as colunas que o usam. Este é o ÚNICO ponto desta change onde o `down`
# não é um `DROP` simples. Aditiva (nenhuma coluna nova, nenhum dado reescrito).
class AddStructureToNotificationType < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute "ALTER TYPE public.notification_type ADD VALUE IF NOT EXISTS 'structure'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Postgres não tem DROP VALUE: remover 'structure' de notification_type " \
          'exigiria recriar o tipo e recompor a coluna notifications.type. ' \
          'Reversão manual e destrutiva — não automatizada de propósito (§D-P8).'
  end
end
