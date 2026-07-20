# frozen_string_literal: true

# A sequência de e-mail é o ponto do exercício: `users.email` tem índice único
# TOTAL, então `create_list(:user, 50)` só persiste se cada um receber um
# endereço distinto.
#
# identity-and-auth 1.5 — a base agora define `password`. Sem isso,
# `encrypted_password` ficaria vazio e, sem `provider`, o CHECK de credencial
# (D4.7 — `provider IS NOT NULL OR encrypted_password <> ''`) recusaria a linha,
# derrubando em silêncio TODO spec a jusante que cria usuário (tenancy,
# user_type_gate, error_response). O trait `:google_only` é o outro caminho:
# `provider` presente, senha ausente.
FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Usuária #{n}" }
    sequence(:email) { |n| "usuaria#{n}@example.com" }
    password { 'senha123' }
    association :user_type, factory: %i[user_type client]

    # Explícito para os specs de senha, ainda que a base já tenha senha.
    trait :with_password do
      password { 'senha123' }
    end

    # Conta criada só por Google: sem senha, com provider verificado. Satisfaz o
    # CHECK de credencial pelo `provider`, não pela senha.
    trait :google_only do
      password { nil }
      provider { 'google_oauth2' }
      sequence(:provider_uid) { |n| "google-uid-#{n}" }
      avatar_url { 'https://lh3.googleusercontent.com/a/default' }
    end

    trait :og do
      association :user_type, factory: %i[user_type og]
    end

    trait :client do
      association :user_type, factory: %i[user_type client]
    end
  end
end
