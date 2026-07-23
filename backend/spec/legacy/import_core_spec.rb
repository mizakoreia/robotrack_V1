# frozen_string_literal: true

require 'rails_helper'
require 'securerandom'

# legacy-data-migration 4.1-4.4 (D-LDM-2, D2) — o núcleo do importador: identidade
# derivada (UUIDv5 do caminho) e idempotência estrutural (ON CONFLICT DO NOTHING).
RSpec.describe 'Legacy — identidade e idempotência do núcleo', :tenancy, type: :model do
  describe 'IdDerivation (4.1)' do
    it 'é determinístico: mesmo caminho → mesmo id' do
      a = Legacy::IdDerivation.robot_id('w', 'p', 'c', 'r')
      b = Legacy::IdDerivation.robot_id('w', 'p', 'c', 'r')
      expect(a).to eq(b)
      expect(a).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'dois robôs homônimos na mesma célula geram ids DISTINTOS (id vs índice)' do
      # R05 com id 'r-2' e outro R05 sem id (posição 2 no array).
      com_id  = { 'id' => 'r-2', 'name' => 'R05' }
      sem_id  = { 'name' => 'R05' }
      ref_a = Legacy::IdDerivation.ref(com_id, 1)
      ref_b = Legacy::IdDerivation.ref(sem_id, 2)

      id_a = Legacy::IdDerivation.robot_id('w', 'p', 'c', ref_a)
      id_b = Legacy::IdDerivation.robot_id('w', 'p', 'c', ref_b)
      expect(id_a).not_to eq(id_b)
    end

    it 'colapsa homônimos de pessoa por caixa (downcase no caminho)' do
      expect(Legacy::IdDerivation.person_id('w', 'João Silva'))
        .to eq(Legacy::IdDerivation.person_id('w', 'joão silva'))
    end
  end

  describe 'Writer idempotente (4.2)' do
    it 'cria no 1º INSERT, pula no 2º (DO NOTHING) e grava legacy_id_map só do criado' do
      ws = make_workspace(name: 'WS Writer')
      run = in_workspace(ws) do
        LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u', file_sha256: 'x' * 64)
      end
      entry = {
        id: Legacy::IdDerivation.project_id(ws.id, 'p1'), legacy_path: 'proj:p1',
        attrs: { workspace_id: ws.id, name: 'Proj Legada', position: 0 }
      }

      r1 = in_workspace(ws) { Legacy::Writer.insert(model: Project, entity_type: 'project', run: run, entries: [entry]) }
      r2 = in_workspace(ws) { Legacy::Writer.insert(model: Project, entity_type: 'project', run: run, entries: [entry]) }

      expect([r1.created, r1.skipped]).to eq([1, 0])
      expect([r2.created, r2.skipped]).to eq([0, 1])
      map = in_workspace(ws) { LegacyIdMap.where(run_id: run.id, entity_type: 'project').count }
      expect(map).to eq(1)
    end
  end

  describe 'contexto e procedência (4.3)' do
    it 'recusa escrever SEM app.current_workspace_id (fail-closed, antes do banco)' do
      entry = { id: SecureRandom.uuid, legacy_path: 'x', attrs: {} }
      expect { Legacy::Writer.insert(model: Project, entity_type: 'project', run: nil, entries: [entry]) }
        .to raise_error(Legacy::ImportContext::ContextMissing)
    end

    it 'recusa arquivo de ownerUid diferente de um run anterior do mesmo workspace' do
      ws = make_workspace(name: 'WS Prov')
      in_workspace(ws) do
        LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-1', file_sha256: 'a' * 64)
      end

      expect do
        Legacy::ImportContext.with_workspace(workspace_id: ws.id, file_owner_uid: 'u-2') { :written }
      end.to raise_error(Legacy::ImportContext::ProvenanceError, /procedência|recusado/i)

      # Mesmo dono passa.
      expect(
        Legacy::ImportContext.with_workspace(workspace_id: ws.id, file_owner_uid: 'u-1') { :ok }
      ).to eq(:ok)
    end
  end

  describe 'idempotência ponta a ponta do núcleo (4.4)' do
    # Reconciliação: a spec 5.8 faz a varredura fim-a-fim das 8 entidades; aqui provamos
    # o MECANISMO (criados: 0 no 2º run + updated_at inalterado) sobre projeto→célula→robô,
    # que é o caminho que carrega a FK e o updated_at.
    def import_tree(ws, run, robot_name)
      Legacy::ImportContext.with_workspace(workspace_id: ws.id, file_owner_uid: 'u-dono') do
        proj_id = Legacy::IdDerivation.project_id(ws.id, 'p1')
        cell_id = Legacy::IdDerivation.cell_id(ws.id, 'p1', 'c1')
        robot_id = Legacy::IdDerivation.robot_id(ws.id, 'p1', 'c1', 'r1')

        r = Legacy::Writer.insert(model: Project, entity_type: 'project', run: run, entries: [
          { id: proj_id, legacy_path: 'proj:p1', attrs: { workspace_id: ws.id, name: 'Proj', position: 0 } }
        ])
        r = r.merge(Legacy::Writer.insert(model: Cell, entity_type: 'cell', run: run, entries: [
          { id: cell_id, legacy_path: 'cell:c1', attrs: { workspace_id: ws.id, project_id: proj_id, name: 'Cell', position: 0 } }
        ]))
        r.merge(Legacy::Writer.insert(model: Robot, entity_type: 'robot', run: run, entries: [
          { id: robot_id, legacy_path: 'robot:r1',
            attrs: { workspace_id: ws.id, cell_id: cell_id, name: robot_name, application: 'Handling', position: 0 } }
        ]))
      end
    end

    it 'segundo run cria 0, não sobrescreve nome renomeado e mantém updated_at' do
      ws = make_workspace(name: 'WS E2E')
      run = in_workspace(ws) do
        LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-dono', file_sha256: 'e' * 64)
      end

      first = import_tree(ws, run, 'Robot A')
      expect(first.created).to eq(3)

      robot_before = in_workspace(ws) { Robot.find(Legacy::IdDerivation.robot_id(ws.id, 'p1', 'c1', 'r1')) }

      second = import_tree(ws, run, 'Robot B RENOMEADO') # nome diferente no 2º run
      expect(second.created).to eq(0)
      expect(second.skipped).to eq(3)

      in_workspace(ws) do
        robot_after = Robot.find(robot_before.id)
        expect(robot_after.name).to eq('Robot A')                 # DO NOTHING, não DO UPDATE
        expect(robot_after.updated_at).to eq(robot_before.updated_at)
        expect(Robot.count).to eq(1)
        expect(Project.count).to eq(1)
        expect(Cell.count).to eq(1)
      end
    end
  end
end
