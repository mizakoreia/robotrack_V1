# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 3.1–3.3 (D-H1/D-H2) — identidade gerada no cliente.
# A metade HTTP (404 byte-idêntico) é provada na suíte de request do G3; aqui
# fica a tabela de decisão em nível de serviço, incluindo o caso cross-tenant.
RSpec.describe 'Identidade do cliente e idempotência', :tenancy do
  describe Hierarchy::IdValidator do
    it 'aceita UUID v4 e v7' do
      expect(described_class.verdict(SecureRandom.uuid)).to eq(:ok)
      expect(described_class.verdict('01890a5d-ac96-774b-bcce-b302099a8057')).to eq(:ok)
    end

    it 'ausente é :absent (o banco gera)' do
      expect(described_class.verdict(nil)).to eq(:absent)
      expect(described_class.verdict('')).to eq(:absent)
    end

    it 'UUID nulo tem veredito PRÓPRIO, distinto de malformado' do
      expect(described_class.verdict('00000000-0000-0000-0000-000000000000')).to eq(:nil_uuid)
      expect(described_class.verdict('não-é-uuid')).to eq(:malformed)
      expect(described_class.verdict('12345678-1234-0234-8234-123456789012')).to eq(:malformed) # versão 0
      expect(described_class.verdict('12345678-1234-4234-c234-123456789012')).to eq(:malformed) # variante errada
    end
  end

  describe Hierarchy::IdempotentCreate do
    let(:ana)   { create(:user) }
    let(:diego) { create(:user) }
    let(:ws_a)  { make_workspace(owner: ana) }
    let(:ws_b)  { make_workspace(owner: diego) }

    def criar(id:, name:, workspace: ws_a)
      in_workspace(workspace) do
        described_class.call(model: Project, attributes: { id: id, name: name }, match_keys: [:name])
      end
    end

    it 'replay do mesmo POST 3 vezes: uma linha, :created depois :replay (201, 200, 200)' do
      id = SecureRandom.uuid
      expect(criar(id: id, name: 'Offline').outcome).to eq(:created)
      expect(criar(id: id, name: 'Offline').outcome).to eq(:replay)
      expect(criar(id: id, name: 'Offline').outcome).to eq(:replay)
      expect(in_workspace(ws_a) { Project.count }).to eq(1)
    end

    it 'mesmo id com carga divergente é :conflict com o recurso atual' do
      id = SecureRandom.uuid
      criar(id: id, name: 'Original')
      resultado = criar(id: id, name: 'Renomeado No Cliente')
      expect(resultado.outcome).to eq(:conflict)
      expect(resultado.record.name).to eq('Original')
    end

    it 'id existente em OUTRO workspace é :not_found — a RLS esconde, a PK não vira oráculo' do
      id = SecureRandom.uuid
      criar(id: id, name: 'De B', workspace: ws_b)

      resultado = criar(id: id, name: 'Tentativa em A')
      expect(resultado.outcome).to eq(:not_found)
      expect(resultado.record).to be_nil
      expect(in_workspace(ws_a) { Project.count }).to eq(0)
    end

    it 'id novo com NOME duplicado no escopo é :name_taken, não :not_found' do
      criar(id: SecureRandom.uuid, name: 'Linha 3')
      resultado = criar(id: SecureRandom.uuid, name: 'linha 3')
      expect(resultado.outcome).to eq(:name_taken)
    end

    it 'workspace_id de OUTRO tenant injetado no attributes é rejeitado pelo WITH CHECK da RLS' do
      # A service do G3 nem declara workspace_id nos params; este teste prova a
      # camada de baixo: mesmo se chegar, o banco não deixa a linha nascer em B.
      # (ws_a/ws_b materializados FORA do bloco: make_workspace dentro de um
      # Tenant.with trocaria o contexto — SET LOCAL sobrevive ao savepoint.)
      ws_a
      ws_b
      id = SecureRandom.uuid
      expect do
        in_workspace(ws_a) do
          described_class.call(model: Project,
                               attributes: { id: id, name: 'Injetado', workspace_id: ws_b.id },
                               match_keys: [:name])
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)

      expect(in_workspace(ws_b) { Project.where(id: id).count }).to eq(0)
    end
  end
end
