# frozen_string_literal: true

require 'rails_helper'

# O template fazia `self.current_user = user if user.present?` sem `else` e sem
# `reject_unauthorized_connection`: uma conexão sem `?token=` era ESTABELECIDA
# com `current_user = nil`, e os canais legados davam `stream_for`
# incondicionalmente a quem chegasse.
RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user, :og) }
  let(:token) { access_token_for(user) }

  it 'rejeita conexão sem token' do
    expect { connect '/cable' }.to have_rejected_connection
  end

  it 'rejeita conexão com token inválido' do
    expect { connect '/cable?token=nao-e-um-jwt' }.to have_rejected_connection
  end

  it 'rejeita conexão cujo token decodifica para um usuário inexistente' do
    orphan = access_token_for(user)
    user.destroy!

    expect { connect "/cable?token=#{orphan}" }.to have_rejected_connection
  end

  it 'aceita conexão com token válido e identifica o usuário' do
    connect "/cable?token=#{token}"

    expect(connection.current_user).to eq(user)
  end

  it 'não deixou nenhum canal legado para trás' do
    channels = Dir.glob(Rails.root.join('app/channels/**/*.rb'))
                  .map { |path| path.sub("#{Rails.root}/", '') }

    expect(channels).to contain_exactly(
      'app/channels/application_cable/channel.rb',
      'app/channels/application_cable/connection.rb'
    )
  end
end
