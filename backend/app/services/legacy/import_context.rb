# frozen_string_literal: true

module Legacy
  # legacy-data-migration 4.3 (D2, D-LDM-1) — o contexto de execução do import. Roda como
  # `robotrack_app` sob RLS: `app.current_workspace_id` é setado POR WORKSPACE (via Tenant),
  # e uma escrita SEM ele setado falha ANTES de tocar o banco (nunca grava no workspace
  # errado). É isto que substitui o "só o dono" que no legado era checagem de runtime: a
  # autoridade vira PROCEDÊNCIA do arquivo (`ownerUid`), verificada contra runs anteriores
  # do mesmo workspace.
  module ImportContext
    ContextMissing  = Class.new(StandardError)
    ProvenanceError = Class.new(StandardError)

    module_function

    # Abre o contexto de tenant do workspace de destino (a ÚNICA porta de escrita do
    # import) e verifica a procedência JÁ DENTRO dele — `legacy_import_runs` é RLS-escopada,
    # então ler runs anteriores exige o contexto aberto. Uma recusa de procedência levanta
    # dentro da transação do Tenant.with: rollback, nada escrito.
    def with_workspace(workspace_id:, file_owner_uid:, user_id: nil)
      Tenant.with(workspace_id: workspace_id, user_id: user_id) do
        verify_provenance!(workspace_id: workspace_id, file_owner_uid: file_owner_uid)
        yield
      end
    end

    # Guarda chamada pelo Writer antes de cada escrita: sem contexto, aborta (fail-closed).
    def require_context!
      return unless Tenant.current_workspace_id.to_s.strip.empty?

      raise ContextMissing,
            'import sem app.current_workspace_id — recusa escrever (nunca no workspace errado)'
    end

    # Procedência: se o workspace já foi importado antes com um ownerUid DIFERENTE, este
    # arquivo é de outro dono — recusa. Um workspace virgem (sem run) estabelece o dono.
    # (O mapeamento ownerUid-Firebase → user Rails não é definido nesta change; a garantia
    # aqui é a COERÊNCIA entre runs do mesmo workspace — o par com o sha256 da 8.4.)
    def verify_provenance!(workspace_id:, file_owner_uid:)
      owner = file_owner_uid.to_s.strip
      raise ProvenanceError, 'ownerUid do arquivo ausente — procedência não verificável' if owner.empty?

      # Dentro do contexto: default_scope + RLS já filtram ao workspace corrente.
      prior = LegacyImportRun.where(workspace_id: workspace_id)
                             .where.not(legacy_owner_uid: owner)
                             .exists?
      return unless prior

      raise ProvenanceError,
            "workspace #{workspace_id} já importado por outro ownerUid — arquivo recusado (procedência)"
    end
  end
end
