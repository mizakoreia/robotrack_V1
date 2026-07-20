# frozen_string_literal: true

# A sequência de e-mail é o ponto do exercício: `users.email` tem índice único,
# então `create_list(:user, 50)` só persiste se cada um receber um endereço
# distinto (test-harness-baseline §Factories).
FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Usuária #{n}" }
    sequence(:email) { |n| "usuaria#{n}@example.com" }
    association :user_type, factory: %i[user_type client]

    trait :og do
      association :user_type, factory: %i[user_type og]
    end

    trait :client do
      association :user_type, factory: %i[user_type client]
    end
  end
end
