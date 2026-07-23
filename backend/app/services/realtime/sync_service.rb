# frozen_string_literal: true

module Realtime
  # realtime-collaboration 4.1 / D6.5 — a reconciliação da reconexão. O cliente
  # guarda o último `seq` visto e, ao (re)conectar, pergunta o que perdeu.
  #
  # Não há log de eventos persistido (não-objetivo): a resposta é DELIBERADAMENTE
  # BURRA. Compara `since` ao `realtime_seq` atual para saber SE perdeu evento, e
  # enumera os TIPOS de entidade tocados por `updated_at`/`created_at`/`deleted_at`
  # numa janela de 10 minutos. Se perdeu evento mas NADA mudou na janela, o que se
  # perdeu é antigo (queda longa) → `gap: true` e o cliente invalida `['ws', w]`
  # inteiro. Uma reconexão longa é rara e um refetch completo é barato para o
  # tamanho de dado do RoboTrack.
  #
  # Roda dentro do contexto de tenant já aberto pelo endpoint (RLS); `unscoped`
  # para enxergar também linhas arquivadas (uma exclusão é uma mudança a invalidar).
  class SyncService
    WINDOW = 10.minutes

    KINDS = {
      'project' => 'Project', 'cell' => 'Cell', 'robot' => 'Robot',
      'task' => 'Task', 'task_advance' => 'TaskAdvance', 'membership' => 'Membership'
    }.freeze

    def self.call(workspace_id:, since:)
      current_seq = Workspace.where(id: workspace_id).pick(:realtime_seq).to_i

      # Sem evento perdido: reconexão limpa, nada a invalidar.
      return { current_seq:, gap: false, entity_kinds: [] } if since.to_i >= current_seq

      kinds = kinds_changed_within(WINDOW.ago)
      gap = kinds.empty? # perdeu evento, mas nada recente ⇒ queda longa
      { current_seq:, gap:, entity_kinds: gap ? [] : kinds }
    end

    def self.kinds_changed_within(since_time)
      KINDS.select { |_kind, model_name| changed_since?(model_name.constantize, since_time) }.keys
    end

    def self.changed_since?(model, since_time)
      cols = model.column_names
      predicates = %w[created_at updated_at deleted_at].select { |c| cols.include?(c) }
                                                       .map { |c| "#{c} >= :t" }
      return false if predicates.empty?

      model.unscoped.where(predicates.join(' OR '), t: since_time).exists?
    end
  end
end
