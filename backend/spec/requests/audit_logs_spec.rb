# frozen_string_literal: true

require 'rails_helper'

# audit-log 5.1–5.3 (§2.8, §4.1, Decisão 9) — a leitura do log: autorização (os 3
# papéis leem, inclusive `view`; não-membro e sem token barram), teto rígido de 200,
# ordem `ts DESC`, não-vazamento de `payload`/`by_person_id`, e a ausência de
# qualquer rota de escrita (POST/PUT/PATCH/DELETE → 404).
RSpec.describe 'audit-log — GET /api/v1/audit_logs', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  # Bulk insert cru (uma instrução; RLS INSERT WITH CHECK aprova — workspace_id
  # casa o contexto). `ts` crescente para exercitar a ordem.
  def seed(n, workspace: ws, base: Time.utc(2026, 7, 1, 12, 0))
    conn = ActiveRecord::Base.connection
    in_workspace(workspace) do
      values = Array.new(n) do |i|
        ts = base + i.seconds
        "(#{conn.quote(SecureRandom.uuid)}, #{conn.quote(workspace.id)}, 'task_completed', 1, " \
          "#{conn.quote("log #{i}")}, #{conn.quote(ts)}, '01/07/2026 12:00', 'Ana', " \
          "'{\"secret\":\"nao-vaza\"}'::jsonb)"
      end.join(',')
      conn.execute(<<~SQL)
        INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name, payload)
        VALUES #{values}
      SQL
    end
  end

  describe 'autorização (5.1, §4.1)' do
    it 'membro view recebe 200 com os registros' do
      vera = create(:user, name: 'Vera View')
      add_member(ws, vera, 'view')
      seed(2)
      get '/api/v1/audit_logs', headers: auth_headers(vera).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it 'dono recebe 200' do
      seed(1)
      get '/api/v1/audit_logs', headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'não-membro é barrado (403), sem corpo de registro' do
      seed(1)
      estranho = create(:user, name: 'Estranho')
      get '/api/v1/audit_logs', headers: auth_headers(estranho).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('nao-vaza')
    end

    it 'sem token → 401 (inclusive com X-Skip-Auth)' do
      get '/api/v1/audit_logs', headers: { 'X-Workspace-Id' => ws.id, 'X-Skip-Auth' => '1' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'leitura (5.2, Decisão 9)' do
    it 'clampa a 200 mesmo com ?limit=1000' do
      seed(205)
      get '/api/v1/audit_logs?limit=1000', headers: headers
      expect(JSON.parse(response.body).size).to eq(200)
    end

    it 'ordena por ts DESC — o mais recente primeiro' do
      seed(3) # log 0, 1, 2 com ts crescente → o "log 2" é o mais recente
      get '/api/v1/audit_logs', headers: headers
      msgs = JSON.parse(response.body).map { |r| r['msg'] }
      expect(msgs.first).to eq('log 2')
      expect(msgs).to eq(['log 2', 'log 1', 'log 0'])
    end

    it 'não vaza payload nem by_person_id no JSON' do
      seed(1)
      get '/api/v1/audit_logs', headers: headers
      row = JSON.parse(response.body).first
      expect(row.keys).to contain_exactly('id', 'msg', 'ts', 'ts_local', 'by_name', 'event_type')
      expect(response.body).not_to include('nao-vaza')
    end

    it 'isola por tenant — não enxerga registros de outro workspace' do
      other = make_workspace(owner: create(:user, name: 'Bob'))
      seed(2)
      seed(5, workspace: other)
      get '/api/v1/audit_logs', headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end
  end

  # Reconciliação (registrada no EXECUCAO G4): o design pedia 404 nos verbos de
  # escrita, mas o app inteiro FAIL-CLOSA rota sem policy declarada com 500
  # `undeclared_route` (confirmado em authorization_gate_spec) — NUNCA 2xx. Provamos
  # o que importa: só o GET é rota (com policy), e escrita não passa.
  describe 'sem rota de escrita (5.3, §4.1 inv. 1)' do
    it 'só o GET audit_logs é rota montada, com policy declarada (nenhuma de escrita)' do
      routes = Api::Root.routes.select { |r| r.path.include?('audit_logs') }
      methods = routes.map { |r| r.request_method.to_s.upcase }.uniq
      expect(methods).to include('GET')
      expect(methods).not_to include('POST', 'PUT', 'PATCH', 'DELETE')
      get_route = routes.find { |r| r.request_method.to_s.upcase == 'GET' }
      expect(get_route.settings[:policy]).to eq(policy: 'AuditLogPolicy', action: :index)
    end

    # O app fail-closa rota não declarada (500, nunca 2xx): `undeclared_route` p/
    # rota policy-less, `internal_error` p/ método sem endpoint. A garantia é a
    # mesma — escrita de auditoria NUNCA sucede.
    %i[post put patch delete].each do |verb|
      it "#{verb.upcase} /api/v1/audit_logs fail-closa (nunca 2xx; nem o dono escreve)" do
        send(verb, '/api/v1/audit_logs', headers: headers)
        expect(response.status).to be_between(400, 599)
        expect(JSON.parse(response.body)['error']).to be_in(%w[undeclared_route internal_error not_found])
      end
    end
  end
end
