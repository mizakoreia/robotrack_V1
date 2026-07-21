# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations 6.3 — `APP_URL` e as mensagens pt-BR.
#
# O modo de falha que isto previne: em produção, sem `APP_URL`, o link do convite
# sairia como `http://localhost:5173/convite/…`. Nada falharia no servidor — o
# erro apareceria na caixa de entrada de quem foi convidado, dias depois, sem
# nenhum sinal. Boot é a única hora em que alguém está olhando.
RSpec.describe 'Configuração de link e mensagens' do
  describe AppUrl do
    around do |example|
      original = ENV.fetch('APP_URL', nil)
      example.run
      ENV['APP_URL'] = original
    end

    it 'usa APP_URL quando presente, sem barra dupla' do
      ENV['APP_URL'] = 'https://app.robotrack.com.br/'

      expect(AppUrl.invite_url('rt_inv_ABC')).to eq('https://app.robotrack.com.br/convite/rt_inv_ABC')
    end

    it 'fora de produção cai para o padrão dev-local' do
      ENV['APP_URL'] = nil

      expect(AppUrl.base).to eq(AppUrl::DEV_DEFAULT)
    end

    it 'em produção, a ausência de APP_URL é ERRO explícito, não localhost silencioso' do
      ENV['APP_URL'] = nil
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect { AppUrl.base }.to raise_error(AppUrl::MissingConfiguration, /APP_URL/)
    end
  end

  describe 'mensagens pt-BR (6.4)' do
    let(:traducoes) do
      YAML.load_file(Rails.root.join('config/locales/pt-BR.invitations.yml')).dig('pt-BR', 'invitations')
    end

    # Todos os códigos que os serviços desta change emitem. Se um código novo
    # aparecer sem redação, este exemplo o nomeia — é a diferença entre uma
    # mensagem pensada e um código cru vazando para a tela.
    CODIGOS = %w[
      invitation_not_found invitation_already_used invitation_expired
      invitation_workspace_mismatch invitation_email_mismatch invitation_already_pending
      unexpected_parameter invalid_role invalid_email already_member
      person_email_conflict forbidden
    ].freeze

    it 'toda negação de convite tem redação em pt-BR' do
      faltando = CODIGOS.reject { |codigo| traducoes.dig('errors', codigo).present? }

      expect(faltando).to be_empty, "sem mensagem pt-BR: #{faltando.join(', ')}"
    end

    it 'toda negação de equipe tem redação em pt-BR' do
      %w[membership_not_found owner_is_immutable cannot_remove_owner workspace_access_revoked].each do |codigo|
        expect(traducoes.dig('memberships', 'errors', codigo)).to be_present, "sem mensagem pt-BR: #{codigo}"
      end
    end

    it 'os códigos emitidos pelos serviços estão todos declarados' do
      fontes = Dir[Rails.root.join('app/services/{invitations,memberships}/*.rb')].map { |f| File.read(f) }.join
      emitidos = fontes.scan(/error_response\('([a-z_]+)'/).flatten.uniq

      nao_declarados = emitidos - CODIGOS -
                       %w[membership_not_found owner_is_immutable cannot_remove_owner workspace_access_revoked]

      expect(nao_declarados).to be_empty,
                                "serviços emitem códigos sem redação pt-BR: #{nao_declarados.join(', ')}"
    end
  end
end
