# frozen_string_literal: true

# workspace-invitations §"Entidade Convite" sob RLS (tarefa 1.4 / D-INV-4, D2).
#
# `invitations` é tabela de DOMÍNIO: `workspace_id NOT NULL`, ENABLE + FORCE RLS
# e policy `tenant_isolation`, como a guarda de esquema de tenancy exige.
#
# A EXCEÇÃO DELIBERADA e o motivo dela:
#
# Dois caminhos leem o convite FORA de um workspace corrente, porque o convidado
# ainda não é membro de nada — a pré-visualização pública
# (`GET /api/v1/invitations/:token`) e o próprio aceite. Um `SECURITY DEFINER`
# sozinho NÃO resolveria: `FORCE ROW LEVEL SECURITY` vincula também o DONO da
# tabela, então a função rodando como `robotrack_migrator` continuaria vendo
# zero linhas. E introduzir um papel com BYPASSRLS destruiria a garantia da Onda 1.
#
# A saída é uma segunda cláusula no `USING`, ligada a uma variável de sessão que
# só a função seta: acesso **por token exato**, nunca listagem. Quem não conhece
# o token não obtém nada — `current_setting` devolve NULL, a comparação vira NULL,
# e NULL não é TRUE (fail-closed, o mesmo padrão da Onda 1). O `WITH CHECK`
# permanece PURO de workspace: ler por token não autoriza escrever nada.
class EnableInvitationsRowLevelSecurity < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
      ALTER TABLE invitations FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON invitations
        USING (
          workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR token = NULLIF(current_setting('app.invitation_token', true), '')
        )
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- Único ponto que abre a cláusula acima. Recebe o token, o publica na
      -- sessão como LOCAL (morre no fim da transação — dentro de uma função há
      -- sempre transação, mesmo em statement solto) e devolve NO MÁXIMO a linha
      -- daquele token. Não existe variação "listar": a função não tem outro
      -- parâmetro e o WHERE é igualdade sobre coluna única.
      CREATE FUNCTION invitation_by_token(p_token text)
        RETURNS SETOF invitations
        LANGUAGE plpgsql
        STABLE
        SECURITY DEFINER
        SET search_path = public, pg_temp
      AS $$
      BEGIN
        PERFORM set_config('app.invitation_token', coalesce(p_token, ''), true);
        RETURN QUERY SELECT * FROM invitations WHERE token = p_token;
      END;
      $$;

      REVOKE ALL ON FUNCTION invitation_by_token(text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION invitation_by_token(text) TO robotrack_app;
      GRANT EXECUTE ON FUNCTION invitation_by_token(text) TO robotrack_migrator;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP FUNCTION IF EXISTS invitation_by_token(text);
      DROP POLICY IF EXISTS tenant_isolation ON invitations;
      ALTER TABLE invitations NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE invitations DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
