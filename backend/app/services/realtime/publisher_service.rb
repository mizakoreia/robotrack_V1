# frozen_string_literal: true

module Realtime
  # realtime-collaboration 3.2 / D6.2, D6.5, D6.9 — o ponto ÚNICO de publicação.
  #
  # Publica um envelope PONTEIRO (nunca conteúdo: sem nome, descrição, comentário
  # ou texto de notificação) no stream `ws:<id>:v1` do workspace, para toda
  # mutação de domínio, sempre APÓS o commit.
  #
  # O `seq` é reservado por `UPDATE workspaces SET realtime_seq = realtime_seq + 1
  # RETURNING` — atômico e serializado na linha do workspace, então dois eventos
  # nunca compartilham número. A reserva acontece no `after_commit`: a request de
  # domínio inteira roda numa transação (Tenant::TransactionMiddleware) e o SET
  # LOCAL do tenant morre no COMMIT, então reabrimos o contexto com `Tenant.with`
  # para que a RLS de `workspaces` (WITH CHECK id = current_workspace_id) aceite o
  # UPDATE. Transação abortada nunca chega ao `after_commit` → número não é
  # consumido: a próxima mutação bem-sucedida publica o mesmo `seq`.
  #
  # Falha NUNCA propaga (D6.9): a mutação já commitou. Redis fora do ar deixa o
  # sistema não-ao-vivo, não quebrado — loga estruturado, incrementa o contador de
  # falha (métrica de `delivery-and-observability`) e segue; o cliente reconcilia
  # pela lacuna de `seq` na próxima conexão.
  class PublisherService
    VERB = { created: 'created', updated: 'updated', destroyed: 'deleted' }.freeze
    ENVELOPE_VERSION = 1

    @failure_count = 0

    class << self
      attr_reader :failure_count

      def reset_failure_count!
        @failure_count = 0
      end

      # Chamado pelo concern no `after_commit` de cada create/update/destroy.
      def publish_change(record, action)
        ws_id = record.realtime_workspace_id
        return if ws_id.blank?

        envelope = nil
        Tenant.with(workspace_id: ws_id, user_id: Current.user_id) do
          # O `seq` é reservado PRIMEIRO. O traversal de `scope` (que faz leituras
          # e pode estourar) roda num savepoint: se falhar, volta ao savepoint SEM
          # reverter o UPDATE do seq — o número já avançado vira uma lacuna que o
          # cliente reconcilia, em vez de o evento sumir sem rastro (o que anularia
          # o próprio esquema seq/gap). Sobra só o UPDATE do seq como ponto
          # irredutível: qualquer falha DEPOIS dele deixa a publicação recuperável.
          seq = reserve_seq(ws_id)
          envelope = build_envelope(
            workspace_id: ws_id, seq: seq,
            type: record.realtime_event_type(action),
            entity: record.realtime_entity, scope: safe_scope(record)
          )
        end
        broadcast(envelope)
      rescue StandardError => e
        log_failure(e, type: safe_type(record, action))
      end

      # Publicação AGREGADA (3.5): 1 envelope terminal para uma operação em massa
      # (`robot.batch_created` no lote, `workspace.reset` no reset). `entity` é nil
      # (não aponta uma linha; o cliente invalida pelo `scope`/subárvore). Chamada
      # via `Realtime.after_commit` para sair pós-commit.
      def publish_aggregate(workspace_id:, type:, scope: {}, actor_person_id: nil)
        return if workspace_id.blank?

        envelope = nil
        Tenant.with(workspace_id: workspace_id, user_id: Current.user_id) do
          seq = reserve_seq(workspace_id)
          envelope = build_envelope(
            workspace_id: workspace_id, seq: seq, type: type, entity: nil, scope: scope,
            actor_person_id: actor_person_id || Current.actor_person_id
          )
        end
        broadcast(envelope)
      rescue StandardError => e
        log_failure(e, type: type)
      end

      # Reserva o próximo `seq` do workspace. Precisa de contexto de tenant aberto
      # (o UPDATE passa pela RLS de `workspaces`) e do GRANT de coluna
      # `realtime_seq` ao `robotrack_app` (migration + roles.sql).
      def reserve_seq(workspace_id)
        quoted = ActiveRecord::Base.connection.quote(workspace_id)
        row = ActiveRecord::Base.connection.exec_query(
          "UPDATE workspaces SET realtime_seq = realtime_seq + 1 WHERE id = #{quoted} RETURNING realtime_seq",
          'realtime.reserve_seq'
        )
        Integer(row.first.fetch('realtime_seq'))
      end

      private

      # Traversal de scope isolado num savepoint: uma falha de leitura degrada
      # para `{}` (o cliente invalida a chave da entidade e reconcilia o rollup
      # pela lacuna de seq) sem abortar a transação que já reservou o seq.
      def safe_scope(record)
        ActiveRecord::Base.transaction(requires_new: true) { record.realtime_scope }
      rescue StandardError => e
        Rails.logger.warn({ event: 'realtime_scope_failed', error: e.class.name }.to_json)
        {}
      end

      def build_envelope(workspace_id:, seq:, type:, entity:, scope:, actor_person_id: :default)
        {
          'v' => ENVELOPE_VERSION,
          'seq' => seq,
          'workspace_id' => workspace_id,
          'type' => type,
          'entity' => entity && stringify(entity),
          'scope' => stringify(scope || {}),
          'actor_person_id' => actor_person_id == :default ? Current.actor_person_id : actor_person_id,
          'origin_id' => Current.origin_id,
          'at' => Time.current.utc.iso8601(3)
        }
      end

      def broadcast(envelope)
        return if envelope.nil?

        ActionCable.server.broadcast(WorkspaceChannel.stream_name(envelope['workspace_id']), envelope)
      end

      def stringify(hash)
        hash.transform_keys(&:to_s)
      end

      def log_failure(error, type:)
        @failure_count += 1
        Rails.logger.error(
          { event: 'realtime_publish_failed', type: type, error: error.class.name, message: error.message }.to_json
        )
      end

      def safe_type(record, action)
        record.realtime_event_type(action)
      rescue StandardError
        action.to_s
      end
    end
  end
end
