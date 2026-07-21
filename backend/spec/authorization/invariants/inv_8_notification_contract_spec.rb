# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 8 — notificação nasce com `read = false` e `message` de no
# máximo 500 caracteres (`firestore.rules` L56-60). Os mecanismos (DEFAULT,
# CHECK char_length, params do endpoint ignorando `read`) são da capacidade
# `in-app-notifications`; esta suíte falha/pende até eles chegarem.
RSpec.describe 'Invariante 8 — contrato de criação de notificação' do
  it 'INSERT com message de 501 chars é rejeitado e read nasce false' do
    pending 'bloqueada por in-app-notifications — tabela notifications (CHECK ≤500, ' \
            'DEFAULT read=false) e endpoint de criação ainda não existem'
    raise 'implementar quando in-app-notifications criar a tabela'
  end
end
