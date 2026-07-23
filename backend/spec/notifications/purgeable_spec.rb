# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 8.1 (D-N10) — o scope de expurgo e o uso do índice.
RSpec.describe 'Notification.purgeable', :tenancy do
  let(:ws) { make_workspace }
  let(:conn) { ActiveRecord::Base.connection }

  def seed(recorded_at:, read:)
    in_workspace(ws) do
      person = Person.create!(name: "P #{SecureRandom.hex(4)}")
      id = SecureRandom.uuid
      conn.execute(<<~SQL)
        INSERT INTO notifications
          (id, workspace_id, recipient_person_id, actor_person_id, type, msg,
           author_name_snapshot, recorded_at, ts_local, read, format_version)
        VALUES
          (#{conn.quote(id)}, #{conn.quote(ws.id)}, #{conn.quote(person.id)}, #{conn.quote(person.id)},
           'progress', 'm', 'B', #{conn.quote(recorded_at)}, '', false, 1)
      SQL
      conn.execute("UPDATE notifications SET read = true, read_at = now() WHERE id = #{conn.quote(id)}") if read
      id
    end
  end

  it 'inclui LIDA há mais de 90 dias; exclui não-lida antiga e lida recente' do
    velha_lida = seed(recorded_at: 100.days.ago, read: true)
    seed(recorded_at: 730.days.ago, read: false) # não lida de 2 anos → NÃO consta
    seed(recorded_at: 10.days.ago, read: true)    # lida recente → NÃO consta

    in_workspace(ws) do
      ids = Notification.purgeable.pluck(:id)
      expect(ids).to contain_exactly(velha_lida)
    end
  end

  it 'a consulta de expurgo é INDEX-backed (EXPLAIN, sem Seq Scan)' do
    seed(recorded_at: 100.days.ago, read: true)
    in_workspace(ws) do
      conn.execute('SET LOCAL enable_seqscan = off')
      plan = conn.execute("EXPLAIN #{Notification.purgeable.to_sql}").map { |r| r['QUERY PLAN'] }.join("\n")
      # O planner pode escolher idx_notifications_retention OU idx_notifications_
      # center (ambos indexam workspace_id + recorded_at e cobrem o predicado). O
      # que 8.1 garante é que NÃO há Seq Scan — a retenção não varre milhões.
      expect(plan).to match(/Index (Only )?Scan/)
      expect(plan).not_to include('Seq Scan')
    end
  end
end
