# frozen_string_literal: true

module Hierarchy
  # hierarchy-screens 3.1/3.2 (§3.7, D-D) — a busca SERVER-SIDE. Substring
  # case-insensitive sobre nomes de PROJETO, CÉLULA e ROBÔ (NÃO tarefas). Volta em
  # lista plana já com o `path_label` resolvido no servidor e a rota do destino.
  #
  # Ordem FIXA e previsível: projetos → células → robôs, cada grupo por nome asc
  # (sem ranking — a spec pede substring, não relevância). Orçamento: 3 queries,
  # uma por tipo (D-C). O escopo de tenant é a RLS (D2), não um `WHERE workspace_id`
  # — a query nem menciona o workspace. O termo é ESCAPADO para `%`, `_` e `\` antes
  # do ILIKE: sem isso, buscar `%` viraria "curinga" e devolveria o workspace inteiro.
  module SearchService
    module_function

    def call(term:)
      q = term.to_s.strip
      return { results: [], count: 0 } if q.empty?

      like = "%#{escape_like(q)}%"
      results = project_hits(like) + cell_hits(like) + robot_hits(like)
      { results: results, count: results.length }
    end

    # `%`, `_` e `\` viram literais (escape padrão do ILIKE é a barra invertida).
    def escape_like(str)
      str.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
    end

    def project_hits(like)
      ::Project.where('name ILIKE ?', like).order(:name).pluck(:id, :name).map do |id, name|
        {
          type: 'project', id: id, name: name,
          path_label: I18n.t('hierarchy.search.path.project', locale: :'pt-BR'),
          route: "/projeto/#{id}"
        }
      end
    end

    def cell_hits(like)
      ::Cell.joins(:project).where('cells.name ILIKE ?', like).order('cells.name')
            .pluck('cells.id', 'cells.name', 'projects.name').map do |id, name, project_name|
        {
          type: 'cell', id: id, name: name,
          path_label: I18n.t('hierarchy.search.path.cell', project: project_name, locale: :'pt-BR'),
          route: "/celula/#{id}"
        }
      end
    end

    def robot_hits(like)
      ::Robot.joins(cell: :project).where('robots.name ILIKE ?', like).order('robots.name')
             .pluck('robots.id', 'robots.name', 'cells.name', 'projects.name')
             .map do |id, name, cell_name, project_name|
        label =
          if cell_name.present? && project_name.present?
            I18n.t('hierarchy.search.path.robot', cell: cell_name, project: project_name, locale: :'pt-BR')
          else
            I18n.t('hierarchy.search.path.robot_orphan', locale: :'pt-BR')
          end
        { type: 'robot', id: id, name: name, path_label: label, route: "/robo/#{id}" }
      end
    end
  end
end
