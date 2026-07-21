# frozen_string_literal: true

module Authorization
  # Carrega e valida `config/authorization/public_routes.yml` UMA vez no boot
  # (2.5 / D3.5). Entrada sem `path`, `method` ou `reason` não-vazio derruba o
  # boot — em vez de virar permissão silenciosa. A conferência de órfãs (entrada
  # cuja rota não existe mais) é do route-sweep, que enxerga `Api::Root.routes`.
  module PublicRoutes
    PATH = 'config/authorization/public_routes.yml'

    class << self
      def entries
        @entries ||= load!
      end

      def include?(method, path)
        entries.any? { |e| e[:method] == method.to_s.upcase && e[:path] == path }
      end

      def load!(file = Rails.root.join(PATH))
        raw = YAML.safe_load_file(file) || []
        raw.map.with_index do |entry, i|
          %w[path method reason].each do |key|
            if entry[key].to_s.strip.empty?
              raise ArgumentError,
                    "#{PATH}: entrada #{i} sem `#{key}` — allowlist pública exige path, method e reason não-vazios (#{entry.inspect})"
            end
          end
          { path: entry['path'], method: entry['method'].upcase, reason: entry['reason'] }
        end.freeze
      end

      # Só para specs exercitarem recarga com arquivo inválido.
      def reset!
        @entries = nil
      end
    end
  end
end
