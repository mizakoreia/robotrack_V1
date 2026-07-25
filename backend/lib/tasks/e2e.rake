# frozen_string_literal: true

# quality-and-accessibility 6.2 / D-QA-2 — o estado inicial de TODO teste E2E vem
# daqui, nunca da UI. Idempotente e determinístico: UUIDs LITERAIS FIXOS (D1
# permite PK do cliente), nunca Faker com semente — o mesmo id no seed é o id que
# o assert cita. Roda como `robotrack_app` (mesmo papel do runtime), abrindo o
# contexto de tenant como o `BootstrapService` faz.
#
# Uso: bundle exec rails 'rt:seed:e2e[base]'
#
# A fonte única dos ids/credenciais é compartilhada com os specs em
# `frontend/e2e/fixtures/seed-constants.ts` — se divergirem, o login E2E falha.
namespace :rt do
  namespace :seed do
    desc 'Semeia o estado E2E determinístico (UUIDs fixos). Cenários: base'
    task :e2e, [:scenario] => :environment do |_t, args|
      E2eSeed.guard_database!
      scenario = (args[:scenario] || 'base').to_s
      case scenario
      when 'base' then E2eSeed.base!
      when 'convite' then E2eSeed.convite!
      when 'avanco' then E2eSeed.convite! # alias: a semente do fluxo 1 serve os dois specs
      when 'troca' then E2eSeed.troca!         # fluxo 3: dois workspaces (WS-E2E + WS-ISCA)
      when 'relatorio' then E2eSeed.relatorio! # fluxo 5: distribuição 18/9/11/2 + ROB-VAZIO
      else abort("[rt:seed:e2e] cenário desconhecido: '#{scenario}' " \
                 '(conhecidos: base, convite, avanco, troca, relatorio)')
      end
      puts "[rt:seed:e2e] cenário '#{scenario}' pronto."
    end
  end
end

# Lógica isolada num módulo do rake (fora de app/, para NÃO ser eager-loaded em
# produção — é ferramenta de teste, não código de runtime).
module E2eSeed
  OWNER = {
    id: '0e2e0000-0000-4000-8000-000000000001',
    name: 'Dona E2E', email: 'owner@e2e.robotrack.local', password: 'e2e-owner-pw-2026'
  }.freeze
  GUEST = {
    id: '0e2e0000-0000-4000-8000-000000000002',
    name: 'Convidado E2E', email: 'guest@e2e.robotrack.local', password: 'e2e-guest-pw-2026'
  }.freeze
  # Terceiro usuário: JÁ é membro `edit`. Existe para a suíte rodar INTEIRA com UMA
  # semente — o spec do convite exige um convidado NÃO-membro, e o spec do avanço
  # exige alguém que já possa escrever. Com um usuário só, um dos dois teria de
  # rodar contra outro estado de banco (ou depender da ordem, que é acoplamento).
  MEMBER = {
    id: '0e2e0000-0000-4000-8000-000000000003',
    name: 'Membro E2E', email: 'member@e2e.robotrack.local', password: 'e2e-member-pw-2026'
  }.freeze
  # Quarto usuário: JÁ é membro `view`. Serve o slice-view de 7.1 (controle fora do
  # DOM + PATCH forjado → 403) sem colidir com o `guest`, que o spec do convite
  # consome como convidado. Espelha MEMBER (edit).
  VIEWER = {
    id: '0e2e0000-0000-4000-8000-000000000004',
    name: 'Espectador E2E', email: 'viewer@e2e.robotrack.local', password: 'e2e-viewer-pw-2026'
  }.freeze
  WORKSPACE = { id: '0e2e0000-0000-4000-8000-0000000000a1', name: 'WS-E2E' }.freeze

  # Hierarquia mínima do cenário [convite]: 1 projeto → 1 célula → 1 robô → 1 tarefa
  # a 40% (o convidado registra +10 → 50). Ids fixos para o assert citar.
  PROJECT = { id: '0e2e0000-0000-4000-8000-0000000000b1', name: 'Linha E2E' }.freeze
  CELL    = { id: '0e2e0000-0000-4000-8000-0000000000c1', name: 'Célula E2E' }.freeze
  ROBOT   = { id: '0e2e0000-0000-4000-8000-0000000000d1', name: 'R01 E2E' }.freeze
  TASK    = { id: '0e2e0000-0000-4000-8000-0000000000e1', desc: 'Soldar ponto A', progress: 40 }.freeze

  # Cenário [troca] (fluxo 3): um SEGUNDO workspace do MESMO dono, com toda a
  # hierarquia prefixada `ISCA-`. Isca do teste de vazamento entre tenants: depois
  # da troca, nenhum texto `ISCA-` pode aparecer nas telas do WS-E2E (e vice-versa).
  ISCA_WORKSPACE = { id: '0e2e0000-0000-4000-8000-0000000000a2', name: 'ISCA-WS' }.freeze
  ISCA_PROJECT   = { id: '0e2e0000-0000-4000-8000-0000000000b2', name: 'ISCA-Projeto' }.freeze
  ISCA_CELL      = { id: '0e2e0000-0000-4000-8000-0000000000c2', name: 'ISCA-Célula' }.freeze
  ISCA_ROBOT     = { id: '0e2e0000-0000-4000-8000-0000000000d2', name: 'ISCA-R99' }.freeze
  ISCA_TASK      = { id: '0e2e0000-0000-4000-8000-0000000000e2', desc: 'ISCA-Soldar', progress: 25 }.freeze

  # Cenário [relatorio] (fluxo 5): um projeto próprio com a distribuição EXATA
  # 18 Concluído / 9 Em Andamento / 11 Pendente / 2 N/A = 40 tarefas (num robô), MAIS
  # ROB-VAZIO (robô sem tarefa) — que TEM de aparecer no documento com 0%, senão o
  # cliente assina um protocolo que omite um robô que existe.
  RPT_PROJECT   = { id: '0e2e0000-0000-4000-8000-0000000000b3', name: 'Relatório E2E' }.freeze
  RPT_CELL      = { id: '0e2e0000-0000-4000-8000-0000000000c3', name: 'Célula Relatório' }.freeze
  RPT_ROBOT     = { id: '0e2e0000-0000-4000-8000-0000000000d3', name: 'ROB-CHEIO' }.freeze
  RPT_EMPTY     = { id: '0e2e0000-0000-4000-8000-0000000000d4', name: 'ROB-VAZIO' }.freeze
  # Distribuição alvo (a soma bate 40): [status, progress, quantidade]. Em Andamento
  # a 62% para o ponderado dos 38 não-N/A dar ~62% (18·100 + 9·62)/38 = 62,05.
  RPT_DISTRIBUTION = [
    ['Concluído', 100, 18],
    ['Em Andamento', 62, 9],
    ['Pendente', 0, 11],
    ['N/A', 0, 2]
  ].freeze

  module_function

  # Cenário CONVITE (fluxo 1): base + uma hierarquia mínima com UMA tarefa a 40%,
  # para o dono convidar o convidado (edit) e o convidado registrar um avanço.
  def convite!
    owner = ensure_user(OWNER)
    ensure_user(GUEST) # NÃO vira membro: é quem o spec do convite convida
    member = ensure_user(MEMBER)
    viewer = ensure_user(VIEWER)
    ensure_workspace(owner)
    ensure_hierarchy(owner)
    ensure_membership(owner, member, 'edit') # já membro: é quem o spec do avanço usa
    ensure_membership(owner, viewer, 'view')  # já membro view: slice-view de 7.1
    puts "[rt:seed:e2e] fluxo1: task=#{TASK[:id]} @#{TASK[:progress]}% em #{ROBOT[:name]}; " \
         "#{GUEST[:email]} NÃO-membro (convite), #{MEMBER[:email]} membro edit (avanço), " \
         "#{VIEWER[:email]} membro view (gating)"
  end

  # RECUSA cair num banco que não seja dedicado a E2E. O par rodou `rt:seed:e2e`
  # contra `robotrack_dev` (era o que estava no ar) e plantou os usuários E2E junto
  # da demo. Pior: os cenários de convite/revogação MUTAM estado, então o banco E2E
  # tem de ser recriado por rodada (idempotência resolve RE-EXECUÇÃO, não
  # CONTAMINAÇÃO entre rodadas). Guarda: nunca em produção; e o nome do banco tem de
  # conter `e2e`/`test` (ou `E2E_SEED_FORCE=1` para um nome fora do padrão).
  def guard_database!
    abort('[rt:seed:e2e] RECUSADO em produção.') if ::Rails.env.production?
    db = ::ActiveRecord::Base.connection.current_database
    return if db =~ /e2e|test/i || ENV['E2E_SEED_FORCE'] == '1'

    abort(
      "[rt:seed:e2e] banco '#{db}' não parece dedicado a E2E (esperado nome com " \
      "'e2e' ou 'test'). Aponte DATABASE_URL para um banco próprio (ex.: robotrack_e2e, " \
      'recriado por rodada) ou passe E2E_SEED_FORCE=1 se souber o que está fazendo.'
    )
  end

  # Cenário BASE: dono + convidado (usuários globais) e o workspace do dono já
  # bootstrapado com o catálogo de 31 tarefas. Alicerce do smoke do harness e dos
  # fluxos que precisam de duas sessões (1 convite, 4 revogação).
  def base!
    owner = ensure_user(OWNER)
    ensure_user(GUEST) # o login do convidado bootstrapa o workspace DELE (gancho de 1º login)

    ensure_workspace(owner)
    puts "[rt:seed:e2e] base: owner=#{OWNER[:email]} guest=#{GUEST[:email]} ws=#{WORKSPACE[:id]}"
  end

  # Usuário global (sem RLS), idempotente por e-mail. Senha conhecida para o login
  # da fixture. Em re-run, garante que a senha bate (troca de credencial no teste
  # não deve quebrar o login).
  def ensure_user(attrs)
    user = ::User.find_or_initialize_by(email: attrs[:email])
    user.id ||= attrs[:id]
    user.name = attrs[:name]
    user.password = attrs[:password]
    user.save!(validate: false) if user.changed? || user.new_record?
    user
  end

  # Workspace do dono com id FIXO, criado como o BootstrapService (que geraria um
  # id ALEATÓRIO) — mas aqui precisamos do id determinístico que o assert cita. O
  # login posterior do dono acha este por `owner_user_id` e não cria outro. Semeia
  # o catálogo SÓ quando o INSERT de fato inseriu (re-run não recolide no índice).
  def ensure_workspace(owner)
    ::Tenant.with(workspace_id: WORKSPACE[:id], user_id: owner.id) do
      conn = ::ActiveRecord::Base.connection
      inserted = conn.exec_update(
        'INSERT INTO workspaces (id, name, owner_user_id) ' \
        "VALUES (#{q(WORKSPACE[:id])}, #{q(WORKSPACE[:name])}, #{q(owner.id)}) " \
        'ON CONFLICT (id) DO NOTHING'
      )
      if inserted.positive?
        ::Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: WORKSPACE[:id]).call
      end
      # Person do dono, idempotente (sem alvo — people tem 3 índices únicos/ws).
      conn.exec_update(
        'INSERT INTO people (id, workspace_id, name, email, user_id) ' \
        "VALUES (gen_random_uuid(), #{q(WORKSPACE[:id])}, #{q(OWNER[:name])}, " \
        "#{q(OWNER[:email])}, #{q(owner.id)}) ON CONFLICT DO NOTHING"
      )
    end
  end

  # Membership + Person do convidado, idempotente. `ON CONFLICT DO NOTHING` sem
  # alvo: `people` tem TRÊS índices únicos por workspace (e-mail, user_id, nome) e
  # um alvo nomeado cobriria só um — qualquer colisão significa "já existe".
  def ensure_membership(owner, member, role)
    ::Tenant.with(workspace_id: WORKSPACE[:id], user_id: owner.id) do
      conn = ::ActiveRecord::Base.connection
      conn.exec_update(
        'INSERT INTO people (id, workspace_id, name, email, user_id) ' \
        "VALUES (gen_random_uuid(), #{q(WORKSPACE[:id])}, #{q(member.name)}, " \
        "#{q(member.email)}, #{q(member.id)}) ON CONFLICT DO NOTHING"
      )
      person_id = conn.select_value(
        "SELECT id FROM people WHERE workspace_id = #{q(WORKSPACE[:id])} AND user_id = #{q(member.id)}"
      )
      conn.exec_update(
        'INSERT INTO memberships (id, workspace_id, user_id, person_id, role, created_at, updated_at) ' \
        "VALUES (gen_random_uuid(), #{q(WORKSPACE[:id])}, #{q(member.id)}, #{q(person_id)}, " \
        "#{q(role)}, now(), now()) ON CONFLICT DO NOTHING"
      )
    end
  end

  # Projeto→célula→robô→tarefa com ids fixos, idempotente (ON CONFLICT (id) DO
  # NOTHING). Sob o contexto de tenant do workspace, como o app escreve.
  def ensure_hierarchy(owner)
    ::Tenant.with(workspace_id: WORKSPACE[:id], user_id: owner.id) do
      now = ::Time.current
      # `unique_by: :id`: as tabelas têm índice de `position` DEFERRABLE, e o
      # ON CONFLICT implícito não aceita constraint deferrable como arbitro —
      # fixamos o arbitro na PK (idempotência por id).
      ::Project.insert_all([{ id: PROJECT[:id], workspace_id: WORKSPACE[:id], name: PROJECT[:name],
                              position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Cell.insert_all([{ id: CELL[:id], workspace_id: WORKSPACE[:id], project_id: PROJECT[:id], name: CELL[:name],
                           position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Robot.insert_all([{ id: ROBOT[:id], workspace_id: WORKSPACE[:id], cell_id: CELL[:id], name: ROBOT[:name],
                            application: 'Misto / Geral', position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Task.insert_all([{ id: TASK[:id], workspace_id: WORKSPACE[:id], robot_id: ROBOT[:id], cat: 'A. Hardware',
                           desc: TASK[:desc], weight: 1, progress: TASK[:progress], status: 'Em Andamento',
                           position: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Progress::BulkRecompute.call(workspace_id: WORKSPACE[:id])
    end
  end

  # Cenário TROCA (fluxo 3): WS-E2E (com hierarquia) + WS-ISCA (segundo workspace do
  # MESMO dono, tudo prefixado ISCA-). Dois workspaces do dono fazem o seletor de
  # workspace aparecer (>1). A isca prova que a troca LIMPA o cache: nada ISCA-
  # vaza para o WS-E2E, e nenhuma URL profunda cruzada devolve dado do outro tenant.
  def troca!
    owner = ensure_user(OWNER)
    ensure_workspace(owner)
    ensure_hierarchy(owner)
    ensure_isca_workspace(owner)
    puts "[rt:seed:e2e] troca: #{WORKSPACE[:name]} + #{ISCA_WORKSPACE[:name]} (mesmo dono); " \
         "iscas #{ISCA_ROBOT[:name]}/#{ISCA_TASK[:desc]}"
  end

  # Cenário RELATORIO (fluxo 5): um projeto próprio no WS-E2E com a distribuição
  # 18/9/11/2 (40 tarefas num robô) + ROB-VAZIO. Nota: os PERCENTUAIS exatos do
  # documento (ponderado ~62%, contagem 45% = 18/40) e a paginação A4 são
  # calibração de EXECUÇÃO — a casa afina o seed rodando o relatório real; o que é
  # determinístico aqui é a DISTRIBUIÇÃO e a presença de ROB-VAZIO.
  def relatorio!
    owner = ensure_user(OWNER)
    ensure_workspace(owner)
    seed_report_hierarchy(owner)
    puts "[rt:seed:e2e] relatorio: 40 tarefas (18 concluído/9 andamento/11 pendente/2 N-A) em " \
         "#{RPT_ROBOT[:name]} + #{RPT_EMPTY[:name]} vazio (deve aparecer com 0%)"
  end

  def ensure_isca_workspace(owner)
    ::Tenant.with(workspace_id: ISCA_WORKSPACE[:id], user_id: owner.id) do
      conn = ::ActiveRecord::Base.connection
      conn.exec_update(
        'INSERT INTO workspaces (id, name, owner_user_id) ' \
        "VALUES (#{q(ISCA_WORKSPACE[:id])}, #{q(ISCA_WORKSPACE[:name])}, #{q(owner.id)}) " \
        'ON CONFLICT (id) DO NOTHING'
      )
      conn.exec_update(
        'INSERT INTO people (id, workspace_id, name, email, user_id) ' \
        "VALUES (gen_random_uuid(), #{q(ISCA_WORKSPACE[:id])}, #{q(OWNER[:name])}, " \
        "#{q(OWNER[:email])}, #{q(owner.id)}) ON CONFLICT DO NOTHING"
      )
      now = ::Time.current
      ::Project.insert_all([{ id: ISCA_PROJECT[:id], workspace_id: ISCA_WORKSPACE[:id], name: ISCA_PROJECT[:name],
                              position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Cell.insert_all([{ id: ISCA_CELL[:id], workspace_id: ISCA_WORKSPACE[:id], project_id: ISCA_PROJECT[:id],
                           name: ISCA_CELL[:name], position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Robot.insert_all([{ id: ISCA_ROBOT[:id], workspace_id: ISCA_WORKSPACE[:id], cell_id: ISCA_CELL[:id],
                            name: ISCA_ROBOT[:name], application: 'Misto / Geral', position: 0, progress_cache: 0,
                            created_at: now, updated_at: now }], unique_by: :id)
      ::Task.insert_all([{ id: ISCA_TASK[:id], workspace_id: ISCA_WORKSPACE[:id], robot_id: ISCA_ROBOT[:id],
                           cat: 'A. Hardware', desc: ISCA_TASK[:desc], weight: 1, progress: ISCA_TASK[:progress],
                           status: 'Em Andamento', position: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Progress::BulkRecompute.call(workspace_id: ISCA_WORKSPACE[:id])
    end
  end

  def seed_report_hierarchy(owner)
    ::Tenant.with(workspace_id: WORKSPACE[:id], user_id: owner.id) do
      now = ::Time.current
      ::Project.insert_all([{ id: RPT_PROJECT[:id], workspace_id: WORKSPACE[:id], name: RPT_PROJECT[:name],
                              position: 1, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Cell.insert_all([{ id: RPT_CELL[:id], workspace_id: WORKSPACE[:id], project_id: RPT_PROJECT[:id],
                           name: RPT_CELL[:name], position: 0, progress_cache: 0, created_at: now, updated_at: now }], unique_by: :id)
      ::Robot.insert_all([
                           { id: RPT_ROBOT[:id], workspace_id: WORKSPACE[:id], cell_id: RPT_CELL[:id], name: RPT_ROBOT[:name],
                             application: 'Misto / Geral', position: 0, progress_cache: 0, created_at: now, updated_at: now },
                           { id: RPT_EMPTY[:id], workspace_id: WORKSPACE[:id], cell_id: RPT_CELL[:id], name: RPT_EMPTY[:name],
                             application: 'Misto / Geral', position: 1, progress_cache: 0, created_at: now, updated_at: now }
                         ], unique_by: :id)
      rows = []
      i = 0
      RPT_DISTRIBUTION.each do |status, progress, qty|
        qty.times do
          i += 1
          rows << { id: format('0e2e0000-0000-4000-8000-00000010%04d', i), workspace_id: WORKSPACE[:id],
                    robot_id: RPT_ROBOT[:id], cat: 'A. Hardware', desc: "Tarefa #{format('%02d', i)} (#{status})",
                    weight: 1, progress: progress, status: status, position: i, created_at: now, updated_at: now }
        end
      end
      ::Task.insert_all(rows, unique_by: :id)
      ::Progress::BulkRecompute.call(workspace_id: WORKSPACE[:id])
    end
  end

  def q(value)
    ::ActiveRecord::Base.connection.quote(value)
  end
end
