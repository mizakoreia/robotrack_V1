# frozen_string_literal: true

# invite-by-code §"Código curto como representação adicional do convite" (G1 /
# design D1–D3).
#
# Migration ADITIVA: o código curto é uma SEGUNDA representação do MESMO convite,
# não um registro novo. Ele herda a linha, o `workspace_id`, o `email`, o `role` e
# a unicidade de pendente por e-mail que já existem. Só quatro colunas e um caminho
# de lookup nascem aqui.
#
# Por que `code_hash` e não o código em claro (D2): o `token` de 256 bits pode
# viver em claro porque adivinhá-lo é inviável por entropia — ele JÁ é o segredo.
# O código curto é 2⁴⁰ (fraco); em claro, um vazamento de banco vira acesso pronto.
# Guardamos `HMAC-SHA256(pepper, normalize(code))`: o pepper mora FORA do banco
# (credentials/ENV), então o hash não é reconstruível offline sem ele. HMAC (e não
# bcrypt) porque o lookup precisa ser DETERMINÍSTICO para achar a linha por
# igualdade indexada — bcrypt salga por linha e exigiria varredura, que a RLS
# por-linha nem permitiria. O APP computa o HMAC e passa o HASH para a função; o
# pepper nunca entra no banco (nenhum `pg_stat_statements`/log de query o exporia).
#
# O lookup pré-login espelha EXATAMENTE `invitation_by_token` (Onda de
# workspace-invitations): um terceiro ramo no `USING` da policy `tenant_isolation`
# ligado a uma variável de sessão que só a função `invitation_by_code` seta —
# acesso por HASH exato, nunca listagem, sem `BYPASSRLS`. Quem não conhece o código
# não seta a GUC, `current_setting` devolve NULL, a comparação vira NULL, e NULL
# não é TRUE (fail-closed). O `WITH CHECK` permanece PURO de workspace: ler por
# código não autoriza escrever nada.
class AddShortCodeToInvitations < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE invitations
        ADD COLUMN code_hash       text        NULL,
        ADD COLUMN code_expires_at timestamptz NULL,
        ADD COLUMN code_attempts   smallint    NOT NULL DEFAULT 0,
        ADD COLUMN code_locked_at  timestamptz NULL;

      -- Único parcial: a maioria dos convites (via link puro) NÃO terá código, e
      -- múltiplos NULLs coexistem num índice único do Postgres. A cláusula parcial
      -- documenta a intenção e mantém o índice pequeno.
      CREATE UNIQUE INDEX index_invitations_on_code_hash
        ON invitations (code_hash) WHERE code_hash IS NOT NULL;

      -- Terceiro ramo no USING, gêmeo do ramo de token. WITH CHECK inalterado.
      ALTER POLICY tenant_isolation ON invitations
        USING (
          workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR token = NULLIF(current_setting('app.invitation_token', true), '')
          OR code_hash = NULLIF(current_setting('app.invitation_code_hash', true), '')
        );

      -- Único ponto que abre o ramo acima. Recebe o HASH já computado no app (o
      -- pepper nunca chega aqui), publica-o na sessão como LOCAL (morre no fim da
      -- transação — dentro de uma função há sempre transação) e devolve NO MÁXIMO
      -- a linha daquele hash. Não existe variação "listar": o WHERE é igualdade
      -- sobre coluna com índice único.
      CREATE FUNCTION invitation_by_code(p_code_hash text)
        RETURNS SETOF invitations
        LANGUAGE plpgsql
        STABLE
        SECURITY DEFINER
        SET search_path = public, pg_temp
      AS $$
      BEGIN
        PERFORM set_config('app.invitation_code_hash', coalesce(p_code_hash, ''), true);
        RETURN QUERY SELECT * FROM invitations WHERE code_hash = p_code_hash;
      END;
      $$;

      REVOKE ALL ON FUNCTION invitation_by_code(text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION invitation_by_code(text) TO robotrack_app;
      GRANT EXECUTE ON FUNCTION invitation_by_code(text) TO robotrack_migrator;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP FUNCTION IF EXISTS invitation_by_code(text);

      ALTER POLICY tenant_isolation ON invitations
        USING (
          workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR token = NULLIF(current_setting('app.invitation_token', true), '')
        );

      DROP INDEX IF EXISTS index_invitations_on_code_hash;

      ALTER TABLE invitations
        DROP COLUMN IF EXISTS code_hash,
        DROP COLUMN IF EXISTS code_expires_at,
        DROP COLUMN IF EXISTS code_attempts,
        DROP COLUMN IF EXISTS code_locked_at;
    SQL
  end
end
