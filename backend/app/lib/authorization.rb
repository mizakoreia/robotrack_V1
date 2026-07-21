# frozen_string_literal: true

# Namespace da camada de autorização (D3): contexto por request e as exceções
# que o gate do Grape mapeia para o contrato 401/403/404 (D3.12).
module Authorization
  class Error < StandardError; end

  # Papel insuficiente para a action, num recurso do PRÓPRIO workspace.
  class Forbidden < Error; end

  # Recurso fora do tenant OU requisitante sem membership: responde 404,
  # indistinguível de id inexistente (D3.6 — 403 confirmaria existência).
  class NotFound < Error; end

  # Rota montada sem `route_setting :policy` e fora da allowlist pública.
  # Levanta em development/test; em produção vira 500 (fail-closed, D3.4).
  class UndeclaredRouteError < Error; end

  # Ponte para chamadas internas cujo papel JÁ foi resolvido pelo servidor
  # (Workspaces::ResolveCurrentService) — nunca com papel vindo do cliente.
  # O gate do G2 constrói o Context real por request; os services usam isto
  # enquanto a decisão ainda mora dentro deles.
  RoleContext = Struct.new(:role)
end
