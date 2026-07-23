# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 1.6 — as invariantes 4 e 8 vivem no BANCO, exercitadas por
# SQL cru (contornando o model), provando que não dependem do ActiveRecord.
RSpec.describe 'notifications — invariantes de banco', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ws) { make_workspace }

  # recipient, actor e um task real (para o índice de idempotência de assign).
  def setup_context
    in_workspace(ws) do
      recipient = Person.create!(name: 'Ana')
      actor = Person.create!(name: 'Bruno')
      project = Project.create!(name: 'L', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'C', position: 0)
      robot = Robot.create!(cell_id: cell.id, name: 'R03', application: 'Sealing', position: 0)
      task = create_task(robot)
      { recipient: recipient.id, actor: actor.id, task: task.id }
    end
  end

  def insert_sql(ctx, msg:, read: false, type: 'progress', recorded_at: '2026-07-23T14:03:00Z', task_id: nil)
    read_at = read ? "'2026-07-23T15:00:00Z'" : 'NULL'
    task_col = task_id ? "'#{task_id}'" : 'NULL'
    <<~SQL
      INSERT INTO notifications
        (workspace_id, recipient_person_id, actor_person_id, type, msg,
         author_name_snapshot, recorded_at, ts_local, read, read_at, ctx_task_id)
      VALUES
        ('#{ws.id}', '#{ctx[:recipient]}', '#{ctx[:actor]}', '#{type}', '#{msg}',
         'Bruno', '#{recorded_at}', '23/07 14:03', #{read}, #{read_at}, #{task_col})
      RETURNING id
    SQL
  end

  it 'msg de 500 chars passa; 501 levanta CheckViolation (inv. 8)' do
    ctx = setup_context
    in_workspace(ws) do
      expect { conn.execute(insert_sql(ctx, msg: 'a' * 500)) }.not_to raise_error
      expect { conn.execute(insert_sql(ctx, msg: 'a' * 501)) }
        .to raise_error(ActiveRecord::StatementInvalid, /msg_max_500|CheckViolation/)
    end
  end

  it 'INSERT com read=true FALHA (não "corrige" para false) (inv. 8)' do
    ctx = setup_context
    in_workspace(ws) do
      expect { conn.execute(insert_sql(ctx, msg: 'oi', read: true)) }
        .to raise_error(ActiveRecord::StatementInvalid, /read deve ser false/)
    end
  end

  it 'UPDATE tocando msg é rejeitado por inteiro (inv. 4)' do
    ctx = setup_context
    in_workspace(ws) do
      id = conn.select_value(insert_sql(ctx, msg: 'original'))
      # savepoint: o raise aborta só o savepoint, a transação externa sobrevive
      # para os SELECTs de verificação.
      expect do
        conn.transaction(requires_new: true) do
          conn.execute("UPDATE notifications SET msg = 'x', read = true, read_at = now() WHERE id = '#{id}'")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /só read\/read_at/)
      expect(conn.select_value("SELECT msg FROM notifications WHERE id = '#{id}'")).to eq('original')
      expect(conn.select_value("SELECT read FROM notifications WHERE id = '#{id}'")).to be(false)
    end
  end

  it 'marcar como lida (só read/read_at) PASSA; desmarcar é rejeitado (inv. 4)' do
    ctx = setup_context
    in_workspace(ws) do
      id = conn.select_value(insert_sql(ctx, msg: 'oi'))
      expect { conn.execute("UPDATE notifications SET read = true, read_at = now() WHERE id = '#{id}'") }.not_to raise_error
      expect { conn.execute("UPDATE notifications SET read = false, read_at = NULL WHERE id = '#{id}'") }
        .to raise_error(ActiveRecord::StatementInvalid, /desmarcar/)
    end
  end

  it 'a mesma assign duas vezes levanta violação de unicidade (§2.7)' do
    ctx = setup_context
    in_workspace(ws) do
      conn.execute(insert_sql(ctx, msg: 'atrib', type: 'assign', task_id: ctx[:task]))
      expect { conn.execute(insert_sql(ctx, msg: 'atrib', type: 'assign', task_id: ctx[:task])) }
        .to raise_error(ActiveRecord::StatementInvalid, /unique|idempotency/i)
    end
  end

  it 'RLS: o workspace B não vê as notificações do A (inv. 1)' do
    ctx = setup_context
    in_workspace(ws) { conn.execute(insert_sql(ctx, msg: 'do A')) }

    other = make_workspace
    in_workspace(other) do
      expect(conn.select_value('SELECT count(*) FROM notifications').to_i).to eq(0)
    end
  end
end
