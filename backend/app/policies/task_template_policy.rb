# frozen_string_literal: true

# §4.1 linhas 1 e 4 — catálogo de tarefas-base: view lê, owner/edit editam e
# sincronizam. `sync?` cobre a sincronização retroativa (§2.6, tarefa 5.4): o
# endpoint que a consome nasce no G6 (depende da tabela `tasks`, de
# `robot-tasks`); o predicado é declarado aqui, junto com o resto da matriz do
# catálogo, e unit-testado desde já (EXECUCAO 4.1).
class TaskTemplatePolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_catalog,
          update?: :manage_catalog,
          destroy?: :manage_catalog,
          sync?: :manage_catalog
end
