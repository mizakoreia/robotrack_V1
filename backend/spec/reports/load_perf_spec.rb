# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 8.4 (D-R8) — o teste ponta a ponta de CARGA na fronteira
# que distingue "avisa" de "trunca": 2.325 tarefas (> 2.000, aviso) com 3.100
# entradas de histórico (< 5.000, SEM truncamento). Afirma também o orçamento de
# ≤5 queries (constante em N — o mesmo invariante de 1.4, agora sob volume) e um
# teto TOLERANTE de tempo de resposta (a política de progress-rollup/my-tasks: o
# alvo de produção é medido em hardware; no runner só se trava a ordem de
# grandeza).
RSpec.describe 'commissioning-report — carga (2.300 tarefas / 3.100 entradas)', :tenancy, :slow, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers = auth_headers(owner).merge('X-Workspace-Id' => ws.id)
  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  it 'emite com aviso de escopo grande, sem truncamento, em ≤5 queries e tempo tolerante' do
    in_workspace(ws) do
      Person.create!(name: 'Ana', user_id: owner.id)
      # 1 projeto × 5 células × 15 robôs × 31 tarefas = 2.325 (> 2.000, < 8.000)
      seed_progress_load(ws.id, scale: { projects: 1, cells: 5, robots: 15, tasks: 31 })
      expect(Task.count).to eq(2_325)

      # 3.100 entradas legadas espalhadas pelas primeiras 1.550 tarefas (2 por
      # tarefa — nenhuma passa de KEEP_PER_TASK; truncar aqui seria bug).
      now = Time.current
      task_ids = Task.order(:id).limit(1_550).pluck(:id)
      rows = task_ids.flat_map do |tid|
        Array.new(2) do |i|
          { id: SecureRandom.uuid, workspace_id: ws.id, task_id: tid,
            author_name_snapshot: 'Legado', from_progress: 0, to_progress: 50,
            legacy: true, recorded_at: now - i.hours, created_at: now - i.hours }
        end
      end
      rows.each_slice(5000) { |s| TaskAdvance.insert_all!(s) }
      expect(TaskAdvance.count).to eq(3_100)
    end

    t0 = clock
    get '/api/v1/commissioning_report?scope=all', headers: headers
    elapsed = clock - t0

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)

    # avisa (>2.000 tarefas) mas NÃO trunca (<5.000 entradas)
    expect(body['warnings']).to eq([I18n.t('report.v1.warning_large_scope')])
    total_advances = body['tree'].flat_map { |p| p['cells'] }.flat_map { |c| c['robots'] }
                                 .flat_map { |r| r['tasks'] }.sum { |t| t['advances'].size }
    expect(total_advances).to eq(3_100)
    notices = body['tree'].flat_map { |p| p['cells'] }.flat_map { |c| c['robots'] }
                          .flat_map { |r| r['tasks'] }.filter_map { |t| t['truncated_notice'] }
    expect(notices).to eq([])
    expect(body['metadata']['counts']['tasks']).to eq(2_325)

    # ≤5 queries do SERVICE sob volume (mesma contagem de 1.4, aqui de novo
    # porque N+1 por tarefa só aparece com milhares de linhas)
    n = 0
    in_workspace(ws) do
      # o Context é montado pelo GATE antes do service — fica fora da contagem,
      # como no spec de 1.4 (e o set_config do túnel de tenant idem).
      ctx = Authorization::Context.new(user: owner, workspace: Workspace.find(ws.id))
      sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
        sql = p[:sql]
        next if p[:name] == 'SCHEMA' || sql =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET|SHOW)/i

        n += 1
      end
      Reports::CommissioningReportService.new(context: ctx).call(scope: 'all')
      ActiveSupport::Notifications.unsubscribe(sub)
    end
    expect(n).to be <= 5

    # teto tolerante de runner (ordem de grandeza; produção mede em hardware)
    expect(elapsed).to be < 5.0, "emissão levou #{elapsed.round(2)}s (teto tolerante 5s)"
  end
end
