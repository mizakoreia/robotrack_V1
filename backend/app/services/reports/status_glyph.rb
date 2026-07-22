# frozen_string_literal: true

module Reports
  # commissioning-report 4.1 (§3.8, §5.1, D-R10) — os 4 glifos tipográficos do
  # documento. §5.1 proíbe emoji em TODA a UI e declara ESTES como a ÚNICA exceção,
  # fechada. Vivem num mapa único no SERVIDOR, viajam no payload, e um sweep (8.2)
  # falha se qualquer caractere fora de `ASCII + {✓ ◐ ○ —}` aparecer nos textos
  # fixos. São caracteres da fonte (Inter), não ícones — não dependem de fonte de
  # emoji no container nem no tablet.
  module StatusGlyph
    # A ordem é a ordem de exibição da distribuição (§3.8).
    MAP = {
      'Concluído'    => '✓',
      'Em Andamento' => '◐',
      'Pendente'     => '○',
      'N/A'          => '—'
    }.freeze

    STATUSES = MAP.keys.freeze

    module_function

    def for(status)
      MAP.fetch(status, '—')
    end
  end
end
