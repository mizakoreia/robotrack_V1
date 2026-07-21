# frozen_string_literal: true

# robot-tasks 5.5 (§4.1, §2.5, D-RT-8) — criar robôs em lote é comissionamento:
# `owner`/`edit` criam, `view` recebe 403. Mesma action da matriz que o CRUD da
# hierarquia (`manage_commissioning`).
class RobotBatchPolicy < BasePolicy
  permits create?: :manage_commissioning
end
