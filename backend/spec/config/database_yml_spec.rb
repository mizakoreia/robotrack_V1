# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 1.3/1.4 — database.yml sem credencial versionada.
# Reintroduzir um `password:` literal ou uma role antiga quebra o CI nomeando o
# item, em vez de vazar segredo no repositório.
RSpec.describe 'config/database.yml', type: :model do
  let(:yml) { File.read(Rails.root.join('config/database.yml')) }

  it 'não tem nenhum `password:` literal (tudo via DATABASE_URL)' do
    offending = yml.lines.grep(/^\s*password:/)
    expect(offending).to be_empty, "database.yml contém password literal: #{offending.inspect}"
  end

  it 'não referencia as roles/credenciais antigas do template' do
    expect(yml).not_to include('robotrack_user')
    expect(yml).not_to include('silas777')
  end

  it 'todos os ambientes usam `url:` (DATABASE_URL)' do
    require 'yaml'
    require 'erb'
    cfg = YAML.safe_load(ERB.new(yml).result, aliases: true)
    %w[development test production].each do |env|
      expect(cfg[env]).to include('url'), "#{env} deveria usar url: (DATABASE_URL)"
    end
  end
end
