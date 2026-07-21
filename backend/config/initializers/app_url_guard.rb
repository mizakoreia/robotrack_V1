# frozen_string_literal: true

# workspace-invitations 6.3 — `APP_URL` é OBRIGATÓRIA em produção.
#
# O link do convite é montado com ela (`<APP_URL>/convite/<token>`). Sem a
# variável, o padrão dev-local geraria links `http://localhost:5173` em produção
# — e o erro só apareceria na caixa de entrada de quem foi convidado, dias
# depois, sem nenhum sinal no servidor. Falhar no BOOT é a única hora em que
# alguém está olhando.
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  # Tarefas de build/imagem (assets:precompile, db:migrate no deploy) sobem o
  # ambiente sem ter as variáveis de runtime; não é hora de exigir.
  next if ENV['SECRET_KEY_BASE_DUMMY'].present?

  AppUrl.base
end
