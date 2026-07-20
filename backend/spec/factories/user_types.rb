# frozen_string_literal: true

# `hierarchy_level` tem índice único, então a sequência é obrigatória: sem ela,
# a segunda criação de user_type numa mesma suíte já colide.
FactoryBot.define do
  factory :user_type do
    sequence(:name) { |n| "tipo_#{n}" }
    description { 'Tipo de usuário de teste' }
    sequence(:hierarchy_level) { |n| n + 100 }

    # Os dois tipos reais do sistema. `find_or_create` porque o gate de
    # autorização os procura por nome — duplicá-los quebraria User#og?.
    trait :og do
      initialize_with { UserType.where('LOWER(name) = ?', 'og').first_or_initialize }
      name { 'OG' }
      description { 'Super Admin - Acesso total ao sistema' }
      hierarchy_level { 1 }
    end

    trait :client do
      initialize_with { UserType.where('LOWER(name) = ?', 'client').first_or_initialize }
      name { 'client' }
      description { 'Cliente - Usuário padrão do sistema' }
      hierarchy_level { 2 }
    end
  end
end
