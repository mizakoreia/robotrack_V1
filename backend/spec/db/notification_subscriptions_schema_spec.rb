# frozen_string_literal: true

require 'rails_helper'

# notification-preferences G1 (D-P1/D-P2/D2) — as invariantes de esquema de
# `notification_subscriptions` provadas NO BANCO, contornando o model.
RSpec.describe 'Esquema de notification_subscriptions', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ws)   { make_workspace }

  def branch_in(workspace)
    in_workspace(workspace) do
      project = Project.create!(name: 'Linha', position: 0)
      cell = Cell.create!(project_id: project.id, name: 'Célula', position: 0)
      robot = Robot.create!(cell_id: cell.id, name: 'R-01', application: 'Handling', position: 0)
      person = Person.create!(name: 'Ana')
      { project: project.id, cell: cell.id, robot: robot.id, person: person.id }
    end
  end

  describe 'CHECK de exatamente um alvo (D-P1)' do
    it 'dois alvos na mesma linha é abortado' do
      b = branch_in(ws)
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO notification_subscriptions (workspace_id, person_id, scope_project_id, scope_robot_id, state)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote(b[:person])}, #{conn.quote(b[:project])}, #{conn.quote(b[:robot])}, 'mute')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_notif_sub_one_scope|check constraint/)
      end
    end

    it 'nenhum alvo é abortado' do
      b = branch_in(ws)
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO notification_subscriptions (workspace_id, person_id, state)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote(b[:person])}, 'follow')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_notif_sub_one_scope|check constraint/)
      end
    end
  end

  describe 'state fora do enum (D-P2)' do
    it 'valor arbitrário é recusado pelo enum' do
      b = branch_in(ws)
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO notification_subscriptions (workspace_id, person_id, scope_robot_id, state)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote(b[:person])}, #{conn.quote(b[:robot])}, 'watch')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum|notification_subscription_state/)
      end
    end
  end

  describe 'FK composta cross-workspace (D-P1)' do
    it 'apontar para robô de outro workspace é abortado pela FK' do
      b = branch_in(ws)
      outro = make_workspace(owner: create(:user))
      alvo_b = branch_in(outro)
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO notification_subscriptions (workspace_id, person_id, scope_robot_id, state)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote(b[:person])}, #{conn.quote(alvo_b[:robot])}, 'mute')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /fk_notif_sub_robot|violates foreign key/)
      end
    end
  end

  describe 'unicidade por pessoa por alvo (D-P1)' do
    it 'segunda preferência da mesma pessoa para o mesmo robô é recusada' do
      b = branch_in(ws)
      in_workspace(ws) do
        NotificationSubscription.create!(person_id: b[:person], scope_robot_id: b[:robot], state: 'follow')
        expect do
          NotificationSubscription.create!(person_id: b[:person], scope_robot_id: b[:robot], state: 'mute')
        end.to raise_error(ActiveRecord::RecordNotUnique, /uq_notif_sub_person_robot/)
      end
    end

    it 'a mesma pessoa pode ter uma preferência em cada nível' do
      b = branch_in(ws)
      in_workspace(ws) do
        NotificationSubscription.create!(person_id: b[:person], scope_project_id: b[:project], state: 'mute')
        NotificationSubscription.create!(person_id: b[:person], scope_cell_id: b[:cell], state: 'follow')
        NotificationSubscription.create!(person_id: b[:person], scope_robot_id: b[:robot], state: 'mute')
        expect(NotificationSubscription.where(person_id: b[:person]).count).to eq(3)
      end
    end
  end

  describe 'CASCADE ao apagar o alvo (D-P1)' do
    it 'apagar o robô remove as preferências dele' do
      b = branch_in(ws)
      in_workspace(ws) do
        NotificationSubscription.create!(person_id: b[:person], scope_robot_id: b[:robot], state: 'mute')
        conn.execute("DELETE FROM robots WHERE id = #{conn.quote(b[:robot])}")
        expect(NotificationSubscription.where(scope_robot_id: b[:robot]).count).to eq(0)
      end
    end
  end

  describe 'RLS forçada (D2)' do
    it 'tem FORCE RLS e policy tenant_isolation' do
      forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'notification_subscriptions'")
      expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)
      count = conn.select_value(
        "SELECT count(*) FROM pg_policies WHERE tablename = 'notification_subscriptions' AND policyname = 'tenant_isolation'"
      ).to_i
      expect(count).to eq(1)
    end

    it 'preferência de outro workspace é invisível' do
      b = branch_in(ws)
      in_workspace(ws) { NotificationSubscription.create!(person_id: b[:person], scope_robot_id: b[:robot], state: 'mute') }
      outro = make_workspace(owner: create(:user))
      in_workspace(outro) do
        expect(NotificationSubscription.count).to eq(0)
      end
    end
  end
end
