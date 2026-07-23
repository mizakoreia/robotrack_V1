# frozen_string_literal: true

require 'uri'

# Guarda de topologia de Redis (delivery-and-observability 3.2). Duas funções
# apontando para o mesmo `(host, porta, db)` é um bug de produção silencioso:
# pressão de memória num cache `allkeys-lru` passaria a evictar JOBS enfileirados
# ou mensagens de Cable. E um `channel_prefix` ausente deixaria staging entregar
# broadcast a clientes de produção. A lógica é pura e testável; o initializer só
# aborta o boot com o resultado.
module RedisTopology
  # `urls` = { cache: url, queue: url, cable: url }. Devolve as violações (vazio = ok).
  def self.violations(urls, channel_prefix:)
    problems = []

    keyed = urls.transform_values { |u| identity(u) }
    keyed.group_by { |_, id| id }.each_value do |group|
      next if group.size < 2

      funcs = group.map(&:first).join(', ')
      problems << "Redis compartilhado entre #{funcs}: resolvem para o mesmo (host, porta, db); " \
                  'cache evictável e fila/cable não-evictáveis não podem dividir instância.'
    end

    problems << 'cable.yml sem channel_prefix: staging entregaria broadcast a clientes de produção.' if channel_prefix.to_s.strip.empty?

    problems
  end

  def self.identity(url)
    uri = URI.parse(url)
    [uri.host, uri.port || 6379, uri.path.to_s]
  rescue URI::InvalidURIError
    [url, nil, nil]
  end
end
