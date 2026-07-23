# frozen_string_literal: true

require 'rails_helper'

# legacy-data-migration 7.1/7.2 (D11, D-LDM-3) — a prova das TRÊS camadas do sentinela
# "Não Atribuído": (1) normalização o remove do arquivo, (2) o resolver nunca cria a
# Person a partir de NENHUMA das três origens (responsibles, assignees, resp), e (3) o
# BANCO o rejeita por CHECK mesmo num INSERT cru que contorne o model. A armadilha é o
# resolver criar a pessoa a partir de qualquer uma das origens.
RSpec.describe 'Legacy — o sentinela "Não Atribuído" morre em três camadas', :tenancy, type: :model do
  # Sentinela presente em responsibles, em assignees (com variações de caixa/espaço) e em resp.
  def canonical
    {
      'schemaVersion' => 1, 'exportedAt' => '2024-05-01T12:00:00Z',
      'workspace' => { 'id' => 'ws-legacy-1', 'ownerUid' => 'u-dono', 'name' => 'F',
                       'responsibles' => ['Não Atribuído', 'Ana', 'Bruno'] },
      'projects' => [{ 'id' => 'p-1', 'name' => 'P', '_ord' => 1,
                       'cells' => [{ 'id' => 'c-1', 'name' => 'C', 'robots' => [{
                         'id' => 'r-1', 'name' => 'R01', 'application' => 'Handling', 'tasks' => [
                           { 'cat' => 'A', 'desc' => 'Com assignees', 'weight' => 1, 'progress' => 0, 'status' => 'Pendente',
                             'assignees' => ['Ana', 'Não Atribuído', '  não atribuído  '] },
                           { 'cat' => 'A', 'desc' => 'Com resp sentinela', 'weight' => 1, 'progress' => 0, 'status' => 'Pendente',
                             'resp' => 'Não Atribuído' }
                         ]
                       }] }] }]
    }
  end

  def import!
    ws = make_workspace(name: 'WS Sentinela')
    run = in_workspace(ws) { LegacyImportRun.create!(workspace_id: ws.id, legacy_owner_uid: 'u-dono', file_sha256: 's' * 64) }
    Legacy::ImportService.call(canonical: canonical, run: run)
    ws
  end

  # === 7.1 — camadas 1 e 2 (resolver) ===
  it 'nenhuma Person sentinela é criada, de nenhuma das três origens' do
    ws = import!
    in_workspace(ws) do
      expect(Person.where("btrim(lower(name)) IN ('não atribuído', 'nao atribuido')").count).to eq(0)
      # Só Ana e Bruno viram pessoas (o sentinela some de responsibles e de assignees).
      expect(Person.pluck(:name)).to match_array(%w[Ana Bruno])
    end
  end

  it 'sentinela no meio de assignees é removido e o resto entra; resp sentinela → zero responsáveis' do
    ws = import!
    in_workspace(ws) do
      com = Task.find_by(desc: 'Com assignees')
      expect(TaskAssignee.where(task_id: com.id).count).to eq(1) # só Ana
      resp = Task.find_by(desc: 'Com resp sentinela')
      expect(TaskAssignee.where(task_id: resp.id).count).to eq(0)
    end
  end

  # === 7.2 — camada 3 (o banco), prova de que a defesa NÃO é só do model ===
  it 'o Postgres recusa o sentinela por CHECK mesmo num INSERT cru que contorna o model' do
    ws = make_workspace(name: 'WS CHECK')
    in_workspace(ws) do
      expect do
        ActiveRecord::Base.connection.execute(
          "INSERT INTO people (id, workspace_id, name) " \
          "VALUES (gen_random_uuid(), '#{ws.id}', 'Não Atribuído')"
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /people_name_not_sentinel|check/i)
    end
  end
end
