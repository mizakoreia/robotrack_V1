# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 3 — log de auditoria é append-only para TODOS, inclusive o
# dono (`firestore.rules` L49: `allow update, delete: if false`). O mecanismo
# primário (`REVOKE UPDATE, DELETE` na tabela) é da capacidade `audit-log`;
# a policy sem verbo de escrita (D3.9) já vale hoje.
RSpec.describe 'Invariante 3 — audit log append-only', :tenancy, type: :request do
  it 'AuditLogPolicy não define update?/destroy? — a ausência é o contrato (D3.9)' do
    expect(AuditLogPolicy).not_to respond_to(:update?)
    expect(AuditLogPolicy).not_to respond_to(:destroy?)
    expect(AuditLogPolicy).to respond_to(:create?)
    expect(AuditLogPolicy).to respond_to(:index?)
  end

  it 'o banco recusa UPDATE/DELETE de audit_logs vindos do papel da aplicação (REVOKE)' do
    conn  = ActiveRecord::Base.connection
    owner = create(:user, name: 'Ana Dona')
    ws    = make_workspace(owner: owner)
    id    = SecureRandom.uuid

    in_workspace(ws) do
      conn.execute(<<~SQL)
        INSERT INTO audit_logs (id, workspace_id, event_type, format_version, msg, ts, ts_local, by_name)
        VALUES (#{conn.quote(id)}, #{conn.quote(ws.id)}, 'task_completed', 1, 'linha', now(), 'x', 'Ana Dona')
      SQL
    end

    # O papel de app não tem o privilégio (camada 1). `permission denied` do Postgres.
    expect do
      in_workspace(ws) { conn.execute("UPDATE audit_logs SET msg = 'x' WHERE id = #{conn.quote(id)}") }
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)

    expect do
      in_workspace(ws) { conn.execute("DELETE FROM audit_logs WHERE id = #{conn.quote(id)}") }
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end
end
