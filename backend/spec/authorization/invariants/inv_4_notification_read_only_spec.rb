# frozen_string_literal: true

require 'rails_helper'

# §4.1 invariante 4 — a única mutação de notificação permitida a um membro é
# marcar como lida a notificação cujo destinatário é ELE PRÓPRIO (divergência
# D-A: a rule legada L61 deixava marcar a alheia; adotamos a §4.1). A restrição
# de colunas (`hasOnly(['read'])` → trigger) vale para todos, inclusive owner.
RSpec.describe 'Invariante 4 — notificação: só read muda, e só pelo destinatário' do
  papel = Struct.new(:role, :person)
  destinatario = Struct.new(:person_id)

  it 'a policy exige o destinatário — marcar a alheia nega para QUALQUER papel' do
    minha  = destinatario.new('p-clara')
    alheia = destinatario.new('p-bruno')

    %i[owner edit view].each do |role|
      contexto = papel.new(role, Struct.new(:id).new('p-clara'))
      expect(NotificationPolicy.mark_read?(contexto, minha)).to be(true)
      expect(NotificationPolicy.mark_read?(contexto, alheia)).to be(false)
    end
  end

  it 'por HTTP: PATCH com read + outra chave é rejeitado inteiro; trigger cobre o console' do
    pending 'bloqueada por in-app-notifications — a tabela, o endpoint PATCH e o trigger ' \
            'BEFORE UPDATE (só read/read_at/updated_at) entram naquela capacidade'
    raise 'implementar quando in-app-notifications criar tabela e endpoint'
  end
end
