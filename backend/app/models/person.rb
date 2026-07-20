# frozen_string_literal: true

# workspace-membership §"Person" (D-6).
#
# Identidade de domínio desacoplada de `User`: `user_id` é nullable (pessoa sem
# conta pode ser responsável). As garantias fortes (unicidade normalizada de
# nome/e-mail/usuário por workspace, abolição do sentinela "Não Atribuído") vivem
# no BANCO (migration CreatePeople) — o model apenas ecoa o essencial.
class Person < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true

  has_many :memberships, dependent: :restrict_with_exception

  validates :name, presence: true
end
