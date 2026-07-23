# frozen_string_literal: true

require 'active_support/core_ext/digest/uuid'

module Legacy
  # legacy-data-migration 4.1 (D-LDM-2) — a IDENTIDADE de cada registro importado é
  # DERIVADA do caminho legado canônico: `id = uuidv5(NAMESPACE, caminho)`. A idempotência
  # mora na PRIMARY KEY, não numa consulta — a 2ª execução colide na PK e o
  # `ON CONFLICT (id) DO NOTHING` não insere nada, sem corrida entre runs concorrentes.
  #
  # Célula e robô podem não ter id no legado (são posições em array): o caminho usa o
  # id se houver, senão o ÍNDICE na lista (`ref`). Dois robôs homônimos na mesma célula
  # geram ids DISTINTOS porque seus caminhos diferem (id vs índice, ou índice vs índice) —
  # é o caso que a busca-por-nome fundiria num só (alternativa descartada de D-LDM-2).
  module IdDerivation
    # NAMESPACE FIXO do RoboTrack. NUNCA muda — mudá-lo reescreve TODOS os ids derivados
    # e quebra a idempotência de qualquer import já feito. É um UUID arbitrário porém
    # congelado (não é o namespace DNS/URL padrão de propósito).
    NAMESPACE = '6d9a0f3e-6c2b-4b7a-9f1e-2c4d6e8a0b12'

    module_function

    # id-ou-índice: a regra de caminho para entidades que podem não ter id no legado.
    def ref(obj, index)
      id = obj.is_a?(Hash) ? obj['id'] : obj
      id.to_s.strip.empty? ? index.to_s : id.to_s
    end

    # uuidv5 sobre uma string de caminho canônica.
    def uuid(path)
      Digest::UUID.uuid_v5(NAMESPACE, path)
    end

    # --- construtores de caminho por entidade (determinísticos) ---

    def workspace_path(ws_id) = "ws:#{ws_id}"
    def project_path(ws_id, proj_id) = "#{workspace_path(ws_id)}/proj:#{proj_id}"
    def cell_path(ws_id, proj_id, cell_ref) = "#{project_path(ws_id, proj_id)}/cell:#{cell_ref}"

    def robot_path(ws_id, proj_id, cell_ref, robot_ref)
      "#{cell_path(ws_id, proj_id, cell_ref)}/robot:#{robot_ref}"
    end

    def task_path(robot_path, task_ref) = "#{robot_path}/task:#{task_ref}"
    def advance_path(task_path, history_index) = "#{task_path}/advance##{history_index}"

    # Pessoa é escopada ao workspace pelo próprio caminho (lower(nome)) — o colapso de
    # homônimos por caixa (D-LDM-3) cai naturalmente do downcase.
    def person_path(ws_id, name) = "person:#{ws_id}:#{name.to_s.strip.downcase}"
    def template_path(ws_id, template_ref) = "#{workspace_path(ws_id)}/template:#{template_ref}"
    def membership_path(ws_id, uid) = "#{workspace_path(ws_id)}/member:#{uid}"

    # Açúcar: caminho → uuid, para o chamador não repetir `uuid(project_path(...))`.
    %i[workspace project cell robot task advance person template membership].each do |ent|
      define_method("#{ent}_id") do |*args|
        uuid(public_send("#{ent}_path", *args))
      end
    end
  end
end
