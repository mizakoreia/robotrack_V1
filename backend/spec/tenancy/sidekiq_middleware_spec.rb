# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq'

# tenant-isolation §"Job de domínio recebe workspace_id explícito" (tarefa 4.3).
RSpec.describe Tenant::SidekiqServerMiddleware, :tenancy do
  subject(:middleware) { described_class.new }

  let(:tenant_worker_class) do
    Class.new do
      include Sidekiq::Job
      sidekiq_options tenant: true
    end
  end

  let(:plain_worker_class) do
    Class.new { include Sidekiq::Job }
  end

  it 'abre o contexto do workspace a partir do primeiro argumento' do
    ws = make_workspace
    seen = nil
    middleware.call(tenant_worker_class.new, { 'args' => [ws.id] }, 'default') do
      seen = ActiveRecord::Base.connection.select_value(
        "SELECT current_setting('app.current_workspace_id', true)"
      )
    end
    expect(seen).to eq(ws.id)
  end

  it 'levanta antes do perform quando o job de domínio não traz workspace_id' do
    ran = false
    expect do
      middleware.call(tenant_worker_class.new, { 'args' => [] }, 'default') { ran = true }
    end.to raise_error(ArgumentError, /exige workspace_id/)
    expect(ran).to be(false)
  end

  it 'levanta quando o primeiro argumento não é um uuid' do
    expect do
      middleware.call(tenant_worker_class.new, { 'args' => [42] }, 'default') { nil }
    end.to raise_error(ArgumentError, /exige workspace_id/)
  end

  it 'não abre contexto para job não marcado como tenant' do
    ran = false
    middleware.call(plain_worker_class.new, { 'args' => ['qualquer'] }, 'default') do
      ran = true
      expect(Tenant.current_workspace_id).to be_nil
    end
    expect(ran).to be(true)
  end
end
