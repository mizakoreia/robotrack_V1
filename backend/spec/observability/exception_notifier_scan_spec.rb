# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 4.5 — o rastreio de exceção é o Sentry; nenhum resquício
# de `ExceptionNotifier` pode restar em app/ ou config/. Fecha a janela cega aberta
# quando o template removeu a chamada quebrada.
RSpec.describe 'Varredura de ExceptionNotifier' do
  it 'não há referência a ExceptionNotifier em backend/app ou backend/config' do
    roots = [Rails.root.join('app'), Rails.root.join('config')]
    offenders = roots.flat_map do |root|
      Dir.glob(root.join('**/*.rb')).select { |f| File.read(f).match?(/ExceptionNotifier/) }
    end
    expect(offenders).to be_empty, "ExceptionNotifier ainda referenciado em: #{offenders.join(', ')}"
  end
end
