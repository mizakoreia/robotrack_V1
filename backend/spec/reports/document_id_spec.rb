# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 3.1/3.3 (§3.8, D-R6) — o id `RT-AAAAMMDD-HHMM`, gerado no
# SERVIDOR no fuso do workspace, com zero-padding, e byte a byte igual onde
# aparecer. O relógio do tablet do galpão é errado — o id de um documento assinado
# não pode vir do cliente.
RSpec.describe Reports::DocumentId do
  it '14:32 de 20/07/2026 no fuso do workspace → RT-20260720-1432' do
    instant = Time.utc(2026, 7, 20, 17, 32) # 17:32 UTC = 14:32 America/Sao_Paulo (UTC-3)
    expect(described_class.for(instant, 'America/Sao_Paulo')).to eq('RT-20260720-1432')
  end

  it 'zero-padding de mês, dia e hora: 05/03/2026 09:07 → RT-20260305-0907' do
    instant = Time.utc(2026, 3, 5, 12, 7) # 12:07 UTC = 09:07 SP
    expect(described_class.for(instant, 'America/Sao_Paulo')).to eq('RT-20260305-0907')
  end

  it 'converte pelo FUSO, não pelo UTC: 02:59Z → 23:59 do dia anterior em SP' do
    instant = Time.utc(2026, 7, 20, 2, 59) # 02:59 UTC = 23:59 de 19/07 em SP
    expect(described_class.for(instant, 'America/Sao_Paulo')).to eq('RT-20260719-2359')
  end

  it 'usa o default America/Sao_Paulo quando o fuso não é informado' do
    expect(described_class.for(Time.utc(2026, 7, 20, 17, 32))).to eq('RT-20260720-1432')
  end

  it 'fuso inválido cai no default sem estourar' do
    expect(described_class.for(Time.utc(2026, 7, 20, 17, 32), 'Fuso/Inexistente')).to eq('RT-20260720-1432')
  end
end
