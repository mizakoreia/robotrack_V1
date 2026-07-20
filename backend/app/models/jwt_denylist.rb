# frozen_string_literal: true

# Estratégia de revogação de JWT por denylist (D4.1). Um token é considerado
# revogado quando seu `jti` está nesta tabela. A verificação em si é feita pelo
# middleware do Warden (devise-jwt) a cada request autenticado; o índice ÚNICO em
# `jti` (migration 1.2) garante que uma revogação concorrente não grave duas
# linhas.
#
# A tabela já existia morta no template (`jwt.dispatch_requests`/
# `revocation_requests` vazios); esta onda a liga de verdade — a config de
# dispatch/revogação vive no initializer do Devise (G2).
class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  self.table_name = 'jwt_denylist'
end
