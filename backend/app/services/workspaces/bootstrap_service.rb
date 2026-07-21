# frozen_string_literal: true

module Workspaces
  # workspace-core §"Bootstrap do workspace no primeiro login" (tarefas 5.1, 5.2 / D-10).
  #
  # Idempotente e seguro sob concorrência (celular + desktop logando ao mesmo
  # tempo, cenário real do produto). Chamado pelo gancho de primeiro login de
  # `identity-and-auth` e, defensivamente, por quem precise garantir o workspace
  # do dono. Cria o workspace, semeia o catálogo padrão de 31 tarefas-base
  # (`task-catalog` §1.3, D-TC-4) na MESMA transação da criação do workspace, e
  # garante a `Person` do dono.
  #
  # O seed do catálogo é chamado DENTRO de `create_idempotently` (não via o
  # evento `workspace.bootstrapped`): §1.3/3.4 exige que ele esteja na mesma
  # transação do INSERT do workspace — um subscriber do evento rodaria fora dela
  # e um workspace poderia commitar sem catálogo. O evento continua emitido para
  # observadores de ciclo de vida, mas não é mais o caminho do seed
  # (EXECUCAO task-catalog, decisão 6).
  #
  # Garantia de concorrência: índice único em `owner_user_id` +
  # `INSERT ... ON CONFLICT (owner_user_id) DO NOTHING` + releitura. O perdedor da
  # corrida não levanta `RecordNotUnique` nem cria segundo workspace — relê e
  # devolve o do vencedor. O id do workspace é gerado pelo cliente (D1): é o que
  # permite abrir o contexto do próprio workspace que estamos criando (o WITH
  # CHECK da RLS exige `id = app.current_workspace_id`).
  class BootstrapService
    def initialize(user:)
      @user = user
    end

    def call
      workspace = find_existing || create_idempotently
      ensure_owner_person(workspace)
      emit_bootstrapped(workspace)
      workspace
    end

    private

    attr_reader :user

    # Lê o workspace do dono. A política de controle de `workspaces` deixa ver a
    # própria linha via `owner_user_id = app.current_user_id`.
    def find_existing
      with_user_context { Workspace.where(owner_user_id: user.id).first }
    end

    def create_idempotently
      new_id = SecureRandom.uuid
      Tenant.with(workspace_id: new_id, user_id: user.id) do
        conn = ActiveRecord::Base.connection
        inserted = conn.exec_update(
          "INSERT INTO workspaces (id, name, owner_user_id) " \
          "VALUES (#{q(new_id)}, #{q(workspace_name)}, #{q(user.id)}) " \
          'ON CONFLICT (owner_user_id) DO NOTHING'
        )
        # Semeia o catálogo (task-catalog §1.3, tarefa 3.4) na MESMA transação e
        # SÓ quando criamos o workspace agora (`inserted == 1`). Se perdemos a
        # corrida (`inserted == 0`), o vencedor já semeou — semear de novo
        # colidiria com o índice único (workspace_id, lower(btrim(desc))). Uma
        # falha no seed reverte o INSERT do workspace acima: nenhum workspace
        # nasce com zero templates.
        SeedDefaultTaskTemplatesService.new(workspace_id: new_id).call if inserted.positive?
      end
      # Relê — pode ser a nossa linha ou a de um vencedor concorrente (id distinto).
      find_existing
    end

    # `Person` do dono, idempotente. Abre o contexto do workspace do vencedor (que
    # pode diferir do id que geramos, se perdemos a corrida).
    #
    # `ON CONFLICT DO NOTHING` SEM alvo, de propósito: `people` tem TRÊS índices
    # únicos por workspace (e-mail, user_id e nome normalizado), e um alvo
    # nomeado cobre um só. A corrida real de dois logins simultâneos colide no
    # índice de E-MAIL antes de chegar ao de `user_id` — com o alvo nomeado, o
    # perdedor levantava `RecordNotUnique` e o bootstrap falhava. Sem alvo,
    # qualquer colisão significa a mesma coisa aqui: a `Person` do dono já
    # existe, não há o que fazer.
    # (Correção de bug pré-existente da Onda 1, exposto pelos specs de
    # concorrência de workspace-invitations.)
    def ensure_owner_person(workspace)
      Tenant.with(workspace_id: workspace.id, user_id: user.id) do
        conn = ActiveRecord::Base.connection
        conn.exec_update(
          'INSERT INTO people (id, workspace_id, name, email, user_id) ' \
          "VALUES (gen_random_uuid(), #{q(workspace.id)}, #{q(person_name)}, " \
          "#{user.email ? q(user.email) : 'NULL'}, #{q(user.id)}) " \
          'ON CONFLICT DO NOTHING'
        )
      end
    end

    def emit_bootstrapped(workspace)
      ActiveSupport::Notifications.instrument(
        'workspace.bootstrapped', workspace_id: workspace.id, owner_user_id: user.id
      )
    end

    def with_user_context
      ActiveRecord::Base.transaction do
        Tenant.set_user!(user.id)
        yield
      end
    end

    # Nome de exibição, caindo para a parte local do e-mail quando vazio — nunca
    # produz "Workspace de " (conta Google sem nome).
    def person_name
      user.display_name.presence || user.email.to_s.split('@').first.presence || 'usuário'
    end

    def workspace_name
      "Workspace de #{person_name}"
    end

    def q(value)
      ActiveRecord::Base.connection.quote(value)
    end
  end
end
