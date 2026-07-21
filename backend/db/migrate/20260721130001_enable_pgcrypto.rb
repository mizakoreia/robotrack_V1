# frozen_string_literal: true

# commissioning-hierarchy 1.1 (D-H1).
#
# `gen_random_uuid()` vem de pgcrypto. Em dev/test desta base a extensão já
# existe (instalada pelo provisionamento, dona = robotrack_migrator — trusted
# no PG16); aqui o CREATE é idempotente. Num ambiente novo sem permissão de
# CREATE EXTENSION, falhamos ANTES das tabelas — melhor um erro nomeado agora
# do que a migration de projects abortar no meio.
class EnablePgcrypto < ActiveRecord::Migration[8.0]
  def up
    execute('CREATE EXTENSION IF NOT EXISTS pgcrypto;')
  rescue ActiveRecord::StatementInvalid => e
    raise ActiveRecord::MigrationError, <<~MSG
      Não foi possível habilitar a extensão pgcrypto (#{e.cause&.class}).
      O papel de migration precisa poder criar extensões TRUSTED (PG13+) ou a
      extensão deve ser pré-instalada por um superusuário — ver
      backend/db/PROVISIONING.md e delivery-and-observability.
    MSG
  end

  def down
    # Não derruba: outras tabelas (workspaces, invitations...) dependem dela.
  end
end
