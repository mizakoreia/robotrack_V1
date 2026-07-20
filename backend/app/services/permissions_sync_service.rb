# frozen_string_literal: true

class PermissionsSyncService
  class << self
    include ApiResponseHandler

    def grant_for_purchase(purchase)
      return validation_error_response('Compra inválida') unless purchase&.user && purchase.plan
      return success_response({}, 200) unless purchase.status == 'DONE'

      user = purchase.user
      plan = purchase.plan
      granted, removed = apply_plan_permissions(user, plan, source: 'plan', source_id: plan.id)
      audit(user, plan, 'grant', granted, removed, 'purchase_done', { purchase_id: purchase.id })
      broadcast(user, granted: granted, removed: removed)
      success_response({ permissions: serialize_user_permissions(user) }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def revoke_for_purchase(purchase)
      return validation_error_response('Compra inválida') unless purchase&.user && purchase.plan

      user = purchase.user
      plan = purchase.plan
      removed = revoke_plan_permissions(user, plan, source: 'plan', source_id: plan.id)
      audit(user, plan, 'revoke', [], removed, 'purchase_revoked', { purchase_id: purchase.id })
      broadcast(user, granted: [], removed: removed)
      success_response({ permissions: serialize_user_permissions(user) }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def sync_for_plan(plan)
      return validation_error_response('Plano inválido') unless plan

      users = Purchase.where(plan_id: plan.id, status: 'DONE').pluck(:user_id).compact
      granted_total = []
      removed_total = []
      User.where(id: users).find_each do |user|
        granted, removed = apply_plan_permissions(user, plan, source: 'plan', source_id: plan.id, replace: true)
        audit(user, plan, 'sync', granted, removed, 'plan_features_changed', {})
        broadcast(user, granted: granted, removed: removed)
        granted_total.concat(granted)
        removed_total.concat(removed)
      end
      success_response({ users_count: users.size, granted: granted_total, removed: removed_total }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def sync_for_user(user)
      return validation_error_response('Usuário inválido') unless user

      plans = Purchase.where(user_id: user.id, status: 'DONE').includes(:plan).map(&:plan).compact
      granted_total = []
      removed_total = []
      plans.each do |plan|
        granted, removed = apply_plan_permissions(user, plan, source: 'plan', source_id: plan.id, replace: true)
        audit(user, plan, 'sync', granted, removed, 'user_sync', {})
        granted_total.concat(granted)
        removed_total.concat(removed)
      end
      broadcast(user, granted: granted_total, removed: removed_total)
      success_response({ permissions: serialize_user_permissions(user) }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def apply_plan_permissions(user, plan, source:, source_id:, replace: false)
      feature_ids = plan.plan_features.pluck(:id)
      perm_ids = PlanFeaturePermission.where(plan_feature_id: feature_ids).pluck(:permission_id).uniq
      now = Time.current
      granted = []
      removed = []
      Permission.where(id: perm_ids).find_each do |perm|
        next if conflict?(user, perm)

        up = UserPermission.where(user_id: user.id, permission_id: perm.id, source: source, source_id: source_id).first
        if up&.revoked_at.present?
          up.update!(revoked_at: nil, granted_at: now)
          granted << perm.key
        elsif up.nil?
          UserPermission.create!(user_id: user.id, permission_id: perm.id, source: source, source_id: source_id,
                                 granted_at: now)
          granted << perm.key
        end
      end
      if replace
        current_perm_ids = UserPermission.where(user_id: user.id, source: source, source_id: source_id,
                                                revoked_at: nil).pluck(:permission_id)
        to_revoke = current_perm_ids - perm_ids
        if to_revoke.any?
          UserPermission.where(user_id: user.id, permission_id: to_revoke, source: source, source_id: source_id,
                               revoked_at: nil).update_all(revoked_at: now)
          removed.concat(Permission.where(id: to_revoke).pluck(:key))
        end
      end
      [granted.uniq, removed.uniq]
    end

    def revoke_plan_permissions(user, _plan, source:, source_id:)
      now = Time.current
      ups = UserPermission.where(user_id: user.id, source: source, source_id: source_id, revoked_at: nil)
      keys = Permission.where(id: ups.pluck(:permission_id)).pluck(:key)
      ups.update_all(revoked_at: now)
      keys
    end

    def conflict?(user, perm)
      conflicts = PermissionConflict.where(permission_id: perm.id).pluck(:conflicts_with_id)
      return false if conflicts.empty?

      UserPermission.where(user_id: user.id, permission_id: conflicts, revoked_at: nil).exists?
    end

    def audit(user, plan, change_type, granted, removed, source_event, metadata)
      PermissionAuditLog.create!(
        user_id: user.id,
        plan_id: plan&.id,
        change_type: change_type,
        permissions_added: granted,
        permissions_removed: removed,
        source_event: source_event,
        metadata: metadata
      )
    end

    def broadcast(user, granted:, removed:)
      payload = { event: 'permissions_changed', user_id: user.id, granted: granted, removed: removed,
                  permissions: serialize_user_permissions(user) }
      PermissionsChannel.broadcast_to("permissions:#{user.id}", payload)
      Rails.logger.info(payload.to_json)
    end

    def serialize_user_permissions(user)
      ups = UserPermission.where(user_id: user.id)
      ups.map do |up|
        {
          key: up.permission.key,
          title: up.permission.title,
          source: up.source,
          granted_at: up.granted_at,
          revoked_at: up.revoked_at
        }
      end
    end
  end
end
