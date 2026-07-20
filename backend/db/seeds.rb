# frozen_string_literal: true

# Seeds do RoboTrack.
#
# O arquivo do template semeava instância de WhatsApp, leads, lead_messages e
# client_applications (SEED_WHATS_INSTANCE, SEED_LEADS, SEED_LEAD_MESSAGES,
# SEED_CLIENT_APPS) — 693 linhas alimentando módulos que não existem mais.
# Sobra o mínimo para um ambiente de desenvolvimento utilizável: os dois tipos
# de usuário e um usuário OG.

puts '📝 Criando tipos de usuário...'
UserType.seed_default_types!

og_type = UserType.og
raise 'Tipo de usuário OG ausente após seed_default_types!' if og_type.nil?

admin_email = ENV.fetch('SEED_OG_EMAIL', 'dev@robotrack.local')

puts '👤 Criando usuário OG de desenvolvimento...'
admin = User.find_or_initialize_by(email: admin_email)
admin.assign_attributes(name: 'Administrador RoboTrack', user_type: og_type)
admin.save!

puts "✅ Seeds concluídas — #{UserType.count} tipos de usuário, OG: #{admin.email}"
