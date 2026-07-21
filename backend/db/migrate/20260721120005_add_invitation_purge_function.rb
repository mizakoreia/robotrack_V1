# frozen_string_literal: true

# workspace-invitations 6.2 / D-INV-9 — expurgo de convites expirados.
#
# O problema que esta migration resolve: o job de expurgo roda FORA de qualquer
# workspace corrente (é manutenção global), e `invitations` tem RLS FORÇADA — o
# `DELETE` do job não enxergaria linha nenhuma. As saídas ruins seriam dar
# `BYPASSRLS` ao runtime (destruiria a garantia da Onda 1) ou rodar um job por
# workspace (que também precisaria listar workspaces sem contexto).
#
# A saída adotada: uma política ADICIONAL de DELETE cujo predicado já é, ele
# mesmo, o critério do expurgo — e uma função `SECURITY DEFINER` que a habilita.
# A exposição é limitada por construção: mesmo quem setasse `app.invitation_purge`
# à mão só alcançaria convites NÃO USADOS e expirados há mais de 30 dias, isto é,
# linhas cujo token já não consome nada e que estão marcadas para morrer. Nenhum
# convite vivo, nenhum consumido (esses são a prova auditável do acesso e estão
# protegidos pelo `ON DELETE RESTRICT` da membership).
class AddInvitationPurgeFunction < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      -- DUAS políticas, e a de SELECT não é opcional: no Postgres, um `DELETE`
      -- cuja cláusula `WHERE` referencia colunas da tabela exige TAMBÉM política
      -- de SELECT — sem ela o expurgo simplesmente não encontra linha nenhuma e
      -- apaga zero, em silêncio. Nenhuma política de INSERT/UPDATE é criada: a
      -- flag não abre caminho de escrita.
      CREATE POLICY purge_expired_select ON invitations
        FOR SELECT
        USING (
          current_setting('app.invitation_purge', true) = 'on'
          AND used_at IS NULL
          AND expires_at < now() - interval '30 days'
        );

      CREATE POLICY purge_expired_delete ON invitations
        FOR DELETE
        USING (
          current_setting('app.invitation_purge', true) = 'on'
          AND used_at IS NULL
          AND expires_at < now() - interval '30 days'
        );

      CREATE FUNCTION purge_expired_invitations()
        RETURNS integer
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = public, pg_temp
      AS $$
      DECLARE
        removidos integer;
      BEGIN
        PERFORM set_config('app.invitation_purge', 'on', true);
        DELETE FROM invitations
         WHERE used_at IS NULL
           AND expires_at < now() - interval '30 days';
        GET DIAGNOSTICS removidos = ROW_COUNT;
        RETURN removidos;
      END;
      $$;

      REVOKE ALL ON FUNCTION purge_expired_invitations() FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION purge_expired_invitations() TO robotrack_app;
      GRANT EXECUTE ON FUNCTION purge_expired_invitations() TO robotrack_migrator;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP FUNCTION IF EXISTS purge_expired_invitations();
      DROP POLICY IF EXISTS purge_expired_delete ON invitations;
      DROP POLICY IF EXISTS purge_expired_select ON invitations;
    SQL
  end
end
