# frozen_string_literal: true

require 'rails_helper'

# progress-advances 2.1 (§1.1, D-IMUT, D-CMT) — o model espelha as CHECKs para
# produzir 422 pt-BR, e é append-only (`readonly?`). A GARANTIA mora no banco
# (spec de esquema); aqui prova-se a camada amigável.
RSpec.describe TaskAdvance, :tenancy do
  let(:ana) { create(:user, name: 'Ana') }
  let(:ws)  { make_workspace(owner: ana) }

  def contexto
    robo = in_workspace(ws) do
      projeto = Project.create!(name: 'L')
      celula = Cell.create!(project_id: projeto.id, name: 'C')
      Robot.create!(cell_id: celula.id, name: 'R')
    end
    in_workspace(ws) do
      tarefa = create_task(robo, desc: 'Power On', position: 0)
      pessoa = Person.create!(name: 'Ana Resp')
      [tarefa, pessoa]
    end
  end

  def build_advance(tarefa, pessoa, **attrs)
    defaults = { task_id: tarefa.id, by: pessoa&.id, author_name_snapshot: 'Ana Resp',
                 from_progress: 0, to_progress: 100, recorded_at: Time.current }
    TaskAdvance.new(defaults.merge(attrs))
  end

  it 'comentário obrigatório abaixo de 100 traz mensagem pt-BR' do
    tarefa, pessoa = contexto
    in_workspace(ws) do
      adv = build_advance(tarefa, pessoa, to_progress: 60, comment: '   ')
      expect(adv).not_to be_valid
      expect(adv.errors[:comment].join).to match(/obrigatório quando o progresso/)
    end
  end

  it 'a 100 dispensa comentário' do
    tarefa, pessoa = contexto
    in_workspace(ws) do
      expect(build_advance(tarefa, pessoa, to_progress: 100, comment: nil)).to be_valid
    end
  end

  it 'autor nulo só vale em entrada legacy (mensagem pt-BR)' do
    tarefa, = contexto
    in_workspace(ws) do
      adv = build_advance(tarefa, nil, to_progress: 0, comment: 'x', legacy: false)
      expect(adv).not_to be_valid
      expect(adv.errors[:by].join).to match(/legada/)

      expect(build_advance(tarefa, nil, to_progress: 0, comment: '(nota anterior)', legacy: true)).to be_valid
    end
  end

  it 'é append-only: um registro persistido é readonly (não salva de novo)' do
    tarefa, pessoa = contexto
    in_workspace(ws) do
      adv = build_advance(tarefa, pessoa).tap(&:save!)
      expect(adv.readonly?).to be(true)
      adv.author_name_snapshot = 'Outro'
      expect { adv.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
