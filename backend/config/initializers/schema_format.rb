# frozen_string_literal: true

# workspace-tenancy (D-4 / tenant-isolation §"Esquema versionado em SQL").
#
# Policy RLS, trigger, `REVOKE` de coluna, `CHECK` com expressão e enum nativo
# NÃO são representáveis em db/schema.rb. Deixar o formato :ruby regeneraria um
# schema.rb silenciosamente SEM a RLS, e o próximo `db:schema:load` (CI, staging,
# máquina nova) nasceria sem isolamento — e verde. Por isso o esquema é
# versionado em db/structure.sql.
Rails.application.config.active_record.schema_format = :sql
