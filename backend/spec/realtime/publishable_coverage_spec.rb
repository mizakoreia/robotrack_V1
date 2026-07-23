# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 3.6 — a trava contra a regressão que originou esta
# proposta: uma entidade de domínio parar de ser "ao vivo" sem ninguém notar.
# Enumera os models que a spec de "Publicação pós-commit" exige e falha NOMEANDO
# qualquer um que não inclua `RealtimePublishable`.
#
# `Notification` está na lista da spec mas o model ainda não existe
# (`in-app-notifications` não construída) — entra aqui como HANDOFF explícito
# quando nascer, para não passar despercebido.
RSpec.describe 'Cobertura de RealtimePublishable nos models de domínio' do
  LIVE_DOMAIN_MODELS = %w[Project Cell Robot Task TaskAdvance Membership].freeze
  PENDING_LIVE_MODELS = %w[Notification].freeze # handoff: in-app-notifications

  LIVE_DOMAIN_MODELS.each do |name|
    it "#{name} inclui RealtimePublishable" do
      model = name.constantize
      expect(model.include?(RealtimePublishable)).to be(true),
        "#{name} é entidade de domínio ao vivo mas não inclui RealtimePublishable — " \
        'sua tela deixaria de atualizar sem ninguém perceber (3.6).'
    end
  end

  it 'registra os models ao vivo ainda inexistentes como handoff (não some da lista)' do
    still_missing = PENDING_LIVE_MODELS.reject { |n| Object.const_defined?(n) }
    # Quando `Notification` nascer, ela cai daqui e deve entrar em LIVE_DOMAIN_MODELS.
    expect(still_missing).to eq(PENDING_LIVE_MODELS)
  end
end
