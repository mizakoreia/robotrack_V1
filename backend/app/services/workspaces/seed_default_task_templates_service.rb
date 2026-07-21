# frozen_string_literal: true

module Workspaces
  # task-catalog 3.3 (§1.3, D-TC-4) — semeia o catálogo padrão (31 tarefas-base)
  # num workspace recém-criado, com UM `insert_all` (não 31 INSERTs).
  #
  # Chamado pelo `BootstrapService`, DENTRO da mesma transação da criação do
  # workspace: um workspace sem catálogo é um workspace quebrado (`robot-tasks`
  # não teria o que copiar). Por isso `insert_all!` (com bang) — se qualquer
  # linha violar CHECK/único, ele levanta e a transação de bootstrap reverte,
  # em vez de deixar um workspace com catálogo parcial.
  #
  # Pressupõe contexto de tenant já aberto com `app.current_workspace_id ==
  # workspace_id` (a RLS avalia o WITH CHECK do INSERT). `insert_all` pula
  # `default_scope` e callbacks, então cada linha traz `workspace_id` explícito
  # (ver `DefaultCatalog.rows_for`).
  class SeedDefaultTaskTemplatesService
    def initialize(workspace_id:)
      @workspace_id = workspace_id
    end

    def call
      TaskTemplate.insert_all!(TaskTemplates::DefaultCatalog.rows_for(@workspace_id))
    end
  end
end
