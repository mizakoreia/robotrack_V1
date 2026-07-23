# frozen_string_literal: true

module Legacy
  # legacy-data-migration 5.2 (D10, D11, D-LDM-3) — o ÚNICO ponto de criação de `Person` no
  # import. Toda origem de nome (responsibles, assignees, resp, membros, notificações) passa
  # por aqui, para que as três garantias valham em UM lugar:
  #   - trim + downcase antes de tudo;
  #   - o sentinela "Não Atribuído" NUNCA vira Person (camada 2 de D-LDM-3 — a 3 é a CHECK);
  #   - homônimos por CAIXA colapsam numa só Person ("João Silva"/"joão silva" → mesmo id,
  #     porque o caminho usa downcase); homônimos por ACENTO ("Joao"/"João") NÃO colapsam
  #     (ids distintos), mas emitem aviso `homonimo_por_acento` no relatório (D10).
  #
  # Idempotente e memoizado: o mesmo nome resolve para o mesmo `person_id` (uuidv5 do
  # caminho) sem reconsultar o banco, e a criação é `ON CONFLICT DO NOTHING` via Writer.
  class AssigneeResolver
    # legacy_ws_id: id do workspace NO ARQUIVO (deriva o person_id, como os demais caminhos).
    # workspace_id: id do workspace de DESTINO (vai na linha, RLS/FK). São diferentes.
    def initialize(legacy_ws_id:, workspace_id:, run:, report:)
      @legacy_ws_id = legacy_ws_id
      @ws_id = workspace_id
      @run = run
      @report = report
      @cache = {}
      @by_deaccent = Hash.new { |h, k| h[k] = [] }
    end

    # Resolve um nome para `person_id`, criando a Person na 1ª vez. Devolve nil para nome
    # ausente/vazio ou sentinela (ausência de responsável = conjunto vazio, nunca a pessoa).
    def resolve(name, email: nil)
      clean = name.to_s.strip
      return nil if clean.empty?
      return nil if IdDerivation.sentinel_name?(clean)

      key = clean.downcase
      return @cache[key] if @cache.key?(key)

      register_accent_homonym(clean, key)
      person_id = IdDerivation.person_id(@legacy_ws_id, clean)
      create_person(person_id, clean, email)
      @cache[key] = person_id
    end

    # Resolve uma lista, descartando nils (sentinela/vazios), preservando ordem e sem
    # duplicar person_ids.
    def resolve_all(names)
      Array(names).filter_map { |n| resolve(n) }.uniq
    end

    private

    def create_person(person_id, name, email)
      attrs = { workspace_id: @ws_id, name: name }
      attrs[:email] = email if email.present?
      result = Writer.insert(
        model: ::Person, entity_type: 'person', run: @run,
        entries: [{ id: person_id, legacy_path: IdDerivation.person_path(@legacy_ws_id, name), attrs: attrs }]
      )
      @report.add_write('person', result)
    end

    # Se o nome sem acento já apareceu com OUTRA grafia acentuada, avisa (não colapsa).
    def register_accent_homonym(clean, key)
      folded = I18n.transliterate(key)
      seen = @by_deaccent[folded]
      if seen.any? && seen.none? { |k| k == key }
        @report.warn!(legacy_path: IdDerivation.person_path(@legacy_ws_id, clean),
                      reason: 'homonimo_por_acento', nome: clean)
      end
      seen << key unless seen.include?(key)
    end
  end
end
