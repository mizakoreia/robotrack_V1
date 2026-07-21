# frozen_string_literal: true

require 'rails_helper'

# task-catalog 1.7 — os cinco casos negativos do esquema provados por SQL CRU,
# com o model fora do caminho. Se algum CHECK/RLS existir só no model, este spec
# passa por baixo dele e falha.
RSpec.describe 'Esquema de task_templates', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user) }
  let(:ws)   { make_workspace(owner: ana) }

  def q(v) = conn.quote(v)

  def insert_cru(workspace_id:, cat: 'A. Hardware', desc: 'Power On', weight: 1, filters: '{}')
    conn.execute(<<~SQL)
      INSERT INTO task_templates (workspace_id, cat, "desc", weight, app_filters)
      VALUES (#{q(workspace_id)}, #{q(cat)}, #{q(desc)}, #{weight}, '#{filters}')
    SQL
  end

  it 'INSERT sem workspace_id não entra — a RLS barra antes mesmo do NOT NULL' do
    in_workspace(ws) do
      expect do
        conn.execute(%(INSERT INTO task_templates (cat, "desc") VALUES ('A', 'B')))
      end.to raise_error(ActiveRecord::StatementInvalid, /row-level security|null value/)
    end
  end

  it 'weight = 0 falha no banco' do
    in_workspace(ws) do
      expect { insert_cru(workspace_id: ws.id, weight: 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_task_templates_weight/)
    end
  end

  it 'app_filters fora do domínio falha' do
    in_workspace(ws) do
      expect { insert_cru(workspace_id: ws.id, filters: '{"solda ponto"}') }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_task_templates_app_filters/)
    end
  end

  it '"Todas" é ACEITO — o importador legado precisa gravá-lo (§1.4 item 3)' do
    in_workspace(ws) do
      insert_cru(workspace_id: ws.id, desc: 'Com Todas', filters: '{"Todas"}')
      expect(conn.select_value(%(SELECT count(*) FROM task_templates WHERE "desc" = 'Com Todas')).to_i).to eq(1)
    end
  end

  it 'app_filters NULL falha (NOT NULL, não default silencioso)' do
    in_workspace(ws) do
      expect do
        conn.execute(<<~SQL)
          INSERT INTO task_templates (workspace_id, cat, "desc", app_filters)
          VALUES (#{q(ws.id)}, 'A', 'B', NULL)
        SQL
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  it 'descrição duplicada normalizada no MESMO workspace falha (23505)' do
    in_workspace(ws) do
      insert_cru(workspace_id: ws.id, desc: 'Payload')
      expect { insert_cru(workspace_id: ws.id, desc: '  payload  ') }
        .to raise_error(ActiveRecord::RecordNotUnique, /lower_desc/)
    end
  end

  it 'a mesma descrição em OUTRO workspace é permitida (catálogo é do workspace)' do
    outro = make_workspace(owner: create(:user))
    in_workspace(ws) { insert_cru(workspace_id: ws.id, desc: 'Payload') }
    in_workspace(outro) { insert_cru(workspace_id: outro.id, desc: 'Payload') }

    expect(in_workspace(ws) { TaskTemplate.count }).to eq(1)
    expect(in_workspace(outro) { TaskTemplate.count }).to eq(1)
  end

  it 'RLS: SELECT sem WHERE não enxerga linha de outro workspace' do
    outro = make_workspace(owner: create(:user))
    in_workspace(outro) { insert_cru(workspace_id: outro.id, desc: 'Do vizinho') }

    visiveis = in_workspace(ws) { conn.select_value('SELECT count(*) FROM task_templates').to_i }
    expect(visiveis).to eq(0)
  end

  it 'RLS: INSERT com workspace_id alheio é rejeitado pelo WITH CHECK' do
    outro = make_workspace(owner: create(:user))
    in_workspace(ws) do
      expect { insert_cru(workspace_id: outro.id, desc: 'Injetada') }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  it 'a tabela tem RLS FORÇADA e a policy tenant_isolation' do
    forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'task_templates'")
    expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)

    policies = conn.select_value(
      "SELECT count(*) FROM pg_policies WHERE tablename = 'task_templates' AND policyname = 'tenant_isolation'"
    ).to_i
    expect(policies).to eq(1)
  end
end
