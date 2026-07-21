# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 3 — log de auditoria é append-only para TODOS, inclusive o
# dono (`firestore.rules` L49: `allow update, delete: if false`). O mecanismo
# primário (`REVOKE UPDATE, DELETE` na tabela) é da capacidade `audit-log`;
# a policy sem verbo de escrita (D3.9) já vale hoje.
RSpec.describe 'Invariante 3 — audit log append-only' do
  it 'AuditLogPolicy não define update?/destroy? — a ausência é o contrato (D3.9)' do
    expect(AuditLogPolicy).not_to respond_to(:update?)
    expect(AuditLogPolicy).not_to respond_to(:destroy?)
    expect(AuditLogPolicy).to respond_to(:create?)
    expect(AuditLogPolicy).to respond_to(:index?)
  end

  it 'o banco recusa UPDATE/DELETE de audit_logs vindos do papel da aplicação' do
    pending 'bloqueada por audit-log — a tabela audit_logs (com REVOKE UPDATE, DELETE ' \
            'para robotrack_app) ainda não existe; a prova é do banco, não da API'
    raise 'implementar quando audit-log criar a tabela e o REVOKE'
  end
end
