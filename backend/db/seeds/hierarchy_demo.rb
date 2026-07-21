# frozen_string_literal: true

# commissioning-hierarchy 7.1 — dataset de desenvolvimento onde um vazamento de
# tenant é visível A OLHO NU: dois workspaces com projetos de MESMO NOME e ids
# adjacentes (só o último dígito difere). Se uma tela mostrar "Linha 1" duas
# vezes, ou o robô do vizinho, o bug não passa despercebido.
#
# Roda como `robotrack_app`, sob `Tenant.with` por workspace — um seed que
# precisasse de BYPASSRLS seria regressão da Onda 1 (EXECUCAO decisão 6).
#
#   RAILS_ENV=development bundle exec rails runner db/seeds/hierarchy_demo.rb

APLICACOES = ['Solda Ponto', 'Solda MIG', 'Handling', 'Misto / Geral'].freeze

def id_par(base, sufixo)
  "#{base}#{sufixo}"
end

def semear_workspace(dono_email:, nome_workspace:, sufixo:)
  dono = User.find_or_initialize_by(email: dono_email)
  dono.assign_attributes(name: "Dona de #{nome_workspace}", password: 'senha-dev-123') if dono.new_record?
  dono.save!

  workspace_id = id_par('11111111-1111-4111-8111-11111111111', sufixo)

  Tenant.with(workspace_id: workspace_id, user_id: dono.id) do
    Workspace.find_or_create_by!(id: workspace_id) do |ws|
      ws.name = nome_workspace
      ws.owner_user_id = dono.id
    end

    pessoa = Person.find_or_create_by!(email: dono.email) do |p|
      p.name = dono.name
      p.user_id = dono.id
    end

    3.times do |p_idx|
      projeto = Project.find_or_create_by!(name: "Linha #{p_idx + 1}") do |pr|
        pr.id = id_par("2222222#{p_idx}-2222-4222-8222-22222222222", sufixo)
        pr.updated_by_person_id = pessoa.id
      end

      2.times do |c_idx|
        celula = Cell.find_or_create_by!(project_id: projeto.id, name: "Célula #{c_idx + 1}") do |ce|
          ce.id = id_par("3333#{p_idx}#{c_idx}3-3333-4333-8333-33333333333", sufixo)
          ce.updated_by_person_id = pessoa.id
        end

        2.times do |r_idx|
          Robot.find_or_create_by!(cell_id: celula.id, name: "R-#{p_idx + 1}#{c_idx + 1}#{r_idx + 1}") do |ro|
            ro.id = id_par("444#{p_idx}#{c_idx}#{r_idx}4-4444-4444-8444-44444444444", sufixo)
            ro.application = APLICACOES[(p_idx + c_idx + r_idx) % APLICACOES.size]
            ro.updated_by_person_id = pessoa.id
          end
        end
      end
    end

    puts "  #{nome_workspace} (#{workspace_id}): #{Project.count} projetos, " \
         "#{Cell.count} células, #{Robot.count} robôs"
  end
end

puts '🏭 Semeando hierarquia de demonstração (2 workspaces × 3 projetos × 2 células × 2 robôs)...'
semear_workspace(dono_email: 'ana@robotrack.local', nome_workspace: 'Fábrica A', sufixo: '1')
semear_workspace(dono_email: 'diego@robotrack.local', nome_workspace: 'Fábrica B', sufixo: '2')
puts '✅ Pronto. Os dois workspaces têm projetos de MESMO nome e ids adjacentes — ' \
     'qualquer vazamento entre tenants aparece na tela.'
