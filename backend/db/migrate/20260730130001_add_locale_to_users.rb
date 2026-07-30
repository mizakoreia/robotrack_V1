# frozen_string_literal: true

# internationalization G6 (D-I6) — a preferência de idioma na CONTA. Migração
# ADITIVA e reversível por `DROP`: uma coluna `locale` em `users`, com default
# `pt-BR` (preserva todo usuário existente) e CHECK restringindo aos dois locales
# suportados (o mesmo par do `available_locales`). É a ÚNICA migração da change.
#
# Habilita: (1) a preferência seguir a pessoa entre dispositivos (o cliente sincroniza
# `rt-lang` ↔ conta); (2) o servidor CONGELAR a notificação no locale do DESTINATÁRIO
# no INSERT (jobs do Sidekiq não têm a requisição/`X-Locale`, então leem daqui).
#
# NÃO toca as tabelas congeladas (`notifications`/`audit_logs`) nem a imutabilidade —
# só acrescenta a fonte de locale. GRANT ao `robotrack_app` é automático (a coluna
# herda os privilégios da tabela `users`; default-privileges do migrator). Reversão =
# `DROP COLUMN` (o `down` abaixo) — não há ponto de reversão não-trivial nesta change.
class AddLocaleToUsers < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE users
        ADD COLUMN locale text NOT NULL DEFAULT 'pt-BR';

      ALTER TABLE users
        ADD CONSTRAINT chk_users_locale CHECK (locale IN ('pt-BR', 'en'));
    SQL
  end

  def down
    execute(<<~SQL)
      ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_locale;
      ALTER TABLE users DROP COLUMN IF EXISTS locale;
    SQL
  end
end
