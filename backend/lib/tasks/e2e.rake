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
      else abort("[rt:seed:e2e] cenário desconhecido: '#{scenario}' (conhecidos: base)")
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
  WORKSPACE = { id: '0e2e0000-0000-4000-8000-0000000000a1', name: 'WS-E2E' }.freeze

  module_function

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

  def q(value)
    ::ActiveRecord::Base.connection.quote(value)
  end
end
