# frozen_string_literal: true

module Api
  module Entities
    # workspace-settings 2.1 (§3.9, D10) — a Person como o painel de Equipe a lê.
    # `has_account` (user_id presente) permite à UI sinalizar quem é MEMBRO (não
    # arquivável por esta tela — o servidor recusa com 409); o nome é o snapshot.
    class Person < Grape::Entity
      expose(:id)          { |o, _| o.id }
      expose(:name)        { |o, _| o.name }
      expose(:has_account) { |o, _| o.user_id.present? }
    end
  end
end
