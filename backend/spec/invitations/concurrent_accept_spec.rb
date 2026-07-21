# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations §"Corrida entre dois consumos do mesmo token"
# (tarefas 3.5 e 3.6 — a verificação central do grupo 3).
#
# Concorrência REAL: threads com conexões distintas do pool, disparadas de um
# latch comum. Nada de mock — a propriedade sob teste é do Postgres (`SELECT …
# FOR UPDATE` serializando dois consumos da MESMA linha), e um dublê provaria
# apenas que o dublê funciona. Era exatamente isto que o legado NÃO tinha: no
# Firestore, marcar o convite como usado e criar a membership eram duas escritas
# independentes, e dois clientes com o mesmo link podiam vencer os dois.
#
# `:tenancy` liga a truncation: sob a transação do RSpec, as linhas criadas pelo
# exemplo seriam invisíveis para as outras conexões e o teste não testaria nada.
RSpec.describe 'Consumo concorrente de convite', :tenancy do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  def create_invitation(email:, role: 'view')
    in_workspace(ws) { Invitation.create!(email: email, role: role, created_by_person: owner_person) }
  end

  # Executa o aceite numa conexão própria, como um segundo processo Puma faria.
  def accept_in_thread(user, token)
    ActiveRecord::Base.connection_pool.with_connection do
      Invitations::AcceptService.new(current_user: user, token: token).call
    end
  ensure
    Tenant.reset_thread_context!
  end

  describe 'mesmo token, duas threads (3.5)' do
    let(:joao) { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }
    let!(:convite) { create_invitation(email: 'joao@fabrica.com', role: 'edit') }

    it 'produz exatamente UM 200 e UM 409, e exatamente UMA membership' do
      largada = Concurrent::CountDownLatch.new(1)

      threads = Array.new(2) do
        Thread.new do
          largada.wait(5)
          accept_in_thread(joao, convite.token)
        end
      end
      largada.count_down
      resultados = threads.map(&:value)

      status = resultados.map { |r| r[:status] }.sort
      expect(status).to eq([200, 409])

      perdedor = resultados.find { |r| r[:status] == 409 }
      expect(perdedor[:error]).to eq('invitation_already_used')

      # Nenhum 500 e nenhum deadlock (o `value` já teria levantado).
      expect(resultados.map { |r| r[:status] }).not_to include(500)

      memberships = in_workspace(ws) { Membership.where(invitation_id: convite.id).to_a }
      expect(memberships.size).to eq(1)
      expect(memberships.first.role).to eq('edit')

      # Uma única `Person` — o perdedor não deixou rastro.
      pessoas = in_workspace(ws) { Person.where(email: 'joao@fabrica.com').count }
      expect(pessoas).to eq(1)

      recarregado = in_workspace(ws) { Invitation.find(convite.id) }
      expect(recarregado.used_by_user_id).to eq(joao.id)
    end

    it 'oito threads simultâneas ainda produzem UMA membership' do
      largada = Concurrent::CountDownLatch.new(1)

      threads = Array.new(8) do
        Thread.new do
          largada.wait(5)
          accept_in_thread(joao, convite.token)
        end
      end
      largada.count_down
      resultados = threads.map(&:value)

      expect(resultados.count { |r| r[:status] == 200 }).to eq(1)
      expect(resultados.count { |r| r[:status] == 409 }).to eq(7)
      expect(in_workspace(ws) { Membership.where(invitation_id: convite.id).count }).to eq(1)
    end
  end

  describe 'tokens distintos não se bloqueiam (3.6)' do
    it 'um convite travado NÃO impede o aceite de outro convite' do
      travado = create_invitation(email: 'travado@fabrica.com')
      livre   = create_invitation(email: 'livre@fabrica.com')
      convidado_livre = create(:user, name: 'Livre Silva', email: 'livre@fabrica.com')

      segurando = Concurrent::CountDownLatch.new(1)
      soltar    = Concurrent::CountDownLatch.new(1)

      guardiao = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Tenant.with(workspace_id: ws.id, user_id: owner.id) do
            Invitation.lock('FOR UPDATE').find(travado.id)
            segurando.count_down
            soltar.wait(10)
          end
        end
      ensure
        Tenant.reset_thread_context!
      end

      expect(segurando.wait(10)).to be(true)

      resultado = Thread.new { accept_in_thread(convidado_livre, livre.token) }.value

      # O ponto: isto aconteceu COM a outra linha ainda travada.
      expect(guardiao).to be_alive
      expect(resultado[:status]).to eq(200)

      soltar.count_down
      guardiao.join(10)
    end

    it '50 aceites concorrentes de 50 tokens distintos, todos bem-sucedidos' do
      convidados = Array.new(50) do |i|
        email = "convidado#{i}@fabrica.com"
        user = create(:user, name: "Convidado #{i}", email: email)
        [user, create_invitation(email: email).token]
      end

      # O teto de paralelismo aqui é o POOL DE CONEXÕES (10 por `database.yml`),
      # não o banco: 50 threads simultâneas apenas esgotariam o pool e o exemplo
      # falharia por `ConnectionTimeoutError` — provando algo sobre o Rails, não
      # sobre o `FOR UPDATE`. Os 50 aceites passam por uma fila servida por
      # `pool - 2` trabalhadores (a folga é da thread principal e do
      # DatabaseCleaner), todos em voo ao mesmo tempo. A prova FINA de que
      # tokens distintos não se bloqueiam é o exemplo anterior, com uma linha
      # travada enquanto outra é consumida.
      fila = Queue.new
      convidados.each { |par| fila << par }
      trabalhadores = [ActiveRecord::Base.connection_pool.size - 2, 2].max

      largada = Concurrent::CountDownLatch.new(1)
      threads = Array.new(trabalhadores) do
        Thread.new do
          largada.wait(15)
          saida = []
          while (par = fila.pop(true) rescue nil)
            saida << accept_in_thread(par[0], par[1])
          end
          saida
        end
      end

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      largada.count_down
      resultados = threads.flat_map(&:value)
      decorrido = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

      expect(resultados.size).to eq(50)
      expect(resultados.map { |r| r[:status] }.uniq).to eq([200])
      expect(in_workspace(ws) { Membership.count }).to eq(50)
      # O `statement_timeout` da transação de aceite é de 5s: se o `FOR UPDATE`
      # serializasse tokens distintos (ou houvesse lock de tabela), o lote
      # estouraria o teto e algum aceite falharia. O tempo total é a evidência
      # complementar — o pool de conexões (10) é o limite real de paralelismo
      # aqui, não o banco.
      expect(decorrido).to be < 30
    end
  end
end
