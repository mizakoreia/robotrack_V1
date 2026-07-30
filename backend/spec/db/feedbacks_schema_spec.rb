# frozen_string_literal: true

require 'rails_helper'

# send-feedback — as invariantes de esquema de `feedbacks` provadas NO BANCO,
# contornando o model: RLS forçada + isolamento, CHECK de tamanho da mensagem,
# CHECK de context-objeto e NOT NULL do workspace_id.
RSpec.describe 'Esquema de feedbacks', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ws)   { make_workspace }

  describe 'RLS forçada' do
    it 'tem FORCE RLS e policy tenant_isolation' do
      forced = conn.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'feedbacks'")
      expect(ActiveModel::Type::Boolean.new.cast(forced)).to be(true)
      count = conn.select_value(
        "SELECT count(*) FROM pg_policies WHERE tablename = 'feedbacks' AND policyname = 'tenant_isolation'"
      ).to_i
      expect(count).to eq(1)
    end

    it 'feedback de outro workspace é invisível' do
      in_workspace(ws) { Feedback.create!(message: 'Olá do WS-A') }
      outro = make_workspace(owner: create(:user))
      in_workspace(outro) { expect(Feedback.count).to eq(0) }
    end
  end

  describe 'CHECK de tamanho da mensagem' do
    it 'mensagem em branco é abortada' do
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO feedbacks (workspace_id, message)
            VALUES (#{conn.quote(ws.id)}, '   ')
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_feedback_message_len|check constraint/)
      end
    end

    it 'mensagem acima de 4000 chars é abortada' do
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO feedbacks (workspace_id, message)
            VALUES (#{conn.quote(ws.id)}, #{conn.quote('a' * 4001)})
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_feedback_message_len|check constraint/)
      end
    end
  end

  describe 'CHECK de context-objeto' do
    it 'context que não é objeto (array) é abortado' do
      in_workspace(ws) do
        expect do
          conn.execute(<<~SQL)
            INSERT INTO feedbacks (workspace_id, message, context)
            VALUES (#{conn.quote(ws.id)}, 'x', '[1,2]'::jsonb)
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_feedback_context_object|check constraint/)
      end
    end
  end

  describe 'workspace_id NOT NULL' do
    it 'INSERT sem workspace_id é abortado' do
      in_workspace(ws) do
        expect do
          conn.execute("INSERT INTO feedbacks (message) VALUES ('sem ws')")
        end.to raise_error(ActiveRecord::StatementInvalid, /null value|not-null|violates/)
      end
    end
  end
end
