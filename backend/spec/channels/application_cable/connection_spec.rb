# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 1.4 — os 5 cenários de "Autenticação da conexão do Cable
# por ticket de vida curta". O template fazia `self.current_user = user if
# user.present?` sem `reject_unauthorized_connection`: uma conexão sem `?token=`
# era ESTABELECIDA com `current_user = nil`. Agora a conexão é autenticada por
# ticket opaco de uso único (60s, GETDEL) e o caminho `?token=` deixou de existir
# — um JWT de sessão na query do handshake não é aceito.
#
# Os tickets vivem no Redis real (`redis-server` de pé na sessão); o adapter do
# Cable em teste é `test`, então o broadcast não depende de Redis.
RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user, :og) }

  it 'aceita a conexão com ticket válido, identifica o dono e consome o ticket' do
    ticket = Realtime::CableTicketService.issue(user)

    connect "/cable?ticket=#{ticket}"

    expect(connection.current_user).to eq(user)
    # uso único: a chave some do Redis após o consumo (GETDEL).
    remaining = Realtime::CableTicketService.with_redis do |r|
      r.get("#{Realtime::CableTicketService::KEY_PREFIX}#{ticket}")
    end
    expect(remaining).to be_nil
  end

  it 'rejeita a segunda conexão com o mesmo ticket (uso único)' do
    ticket = Realtime::CableTicketService.issue(user)
    connect "/cable?ticket=#{ticket}" # primeira consome

    expect { connect "/cable?ticket=#{ticket}" }.to have_rejected_connection
  end

  it 'rejeita ticket expirado (chave já saiu do Redis por TTL)' do
    jti = SecureRandom.urlsafe_base64(24)
    key = "#{Realtime::CableTicketService::KEY_PREFIX}#{jti}"
    # Emite "há 61s": grava com TTL mínimo e deixa o Redis expirar a chave — a via
    # real da expiração, sem esperar 60s de relógio.
    Realtime::CableTicketService.with_redis { |r| r.set(key, user.id.to_s, px: 10) }
    sleep 0.05

    expect { connect "/cable?ticket=#{jti}" }.to have_rejected_connection
  end

  it 'rejeita conexão sem credencial (sem ticket e sem token), não a aceita como anônima' do
    expect { connect '/cable' }.to have_rejected_connection
  end

  it 'rejeita JWT de sessão em query string (o caminho ?token= não existe mais)' do
    token = access_token_for(user)

    expect { connect "/cable?token=#{token}" }.to have_rejected_connection
  end

  it 'não deixou nenhum canal legado para trás (só a base + o WorkspaceChannel)' do
    channels = Dir.glob(Rails.root.join('app/channels/**/*.rb'))
                  .map { |path| path.sub("#{Rails.root}/", '') }

    expect(channels).to contain_exactly(
      'app/channels/application_cable/channel.rb',
      'app/channels/application_cable/connection.rb',
      'app/channels/workspace_channel.rb'
    )
  end
end
