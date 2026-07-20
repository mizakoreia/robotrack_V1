# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PermissionsSyncService, type: :service do
  let!(:feature) { PlanFeature.create!(title: 'Console de Administração') }
  let!(:perm) { Permission.create!(key: 'console_access', title: 'Acesso ao Console') }
  let!(:pfp) { PlanFeaturePermission.create!(plan_feature: feature, permission: perm) }
  let!(:plan) { Plan.create!(title: 'Pro', price: 10, billing_kind: 'subscription') }
  let!(:assignment) { PlanFeatureAssignment.create!(plan: plan, plan_feature: feature, sort_order: 1) }
  let!(:user) { User.create!(email: 'spec@example.com') }
  let!(:purchase) do
    Purchase.create!(identifier: 'ABC123', plan: plan, user: user, value: 10, status: 'PENDING', billing_type: 'PIX',
                     cycle: 'UNIQUE')
  end

  it 'grants permissions when purchase is done' do
    purchase.update!(status: 'DONE')
    ups = UserPermission.where(user_id: user.id, permission_id: perm.id).active
    expect(ups.count).to eq(1)
  end
end
