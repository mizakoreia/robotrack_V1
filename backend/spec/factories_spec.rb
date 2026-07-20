# frozen_string_literal: true

require 'rails_helper'

# Uma factory quebrada deve falhar AQUI, nomeando a factory — não estourar
# dentro de um spec de request meses depois, onde a causa fica a três camadas
# de distância (test-harness-baseline §Factories).
RSpec.describe 'Factories' do
  FactoryBot.factories.each do |factory|
    it "cria :#{factory.name} sem erro" do
      expect { create(factory.name) }.not_to raise_error
    end
  end

  it 'a sequência de e-mail sustenta criação em massa' do
    expect { create_list(:user, 50) }.not_to raise_error
    expect(User.count).to eq(50)
    expect(User.distinct.count(:email)).to eq(50)
  end

  it 'os traits og e client resolvem para os tipos reais do sistema' do
    expect(create(:user, :og)).to be_og
    expect(create(:user, :client)).to be_client
  end
end
