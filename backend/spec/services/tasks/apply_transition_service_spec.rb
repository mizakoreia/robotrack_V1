# frozen_string_literal: true

require 'rails_helper'

# progress-advances 2.3 (§2.2, D-SM, D-CHK) — uma asserção por linha da
# tabela-verdade, incluindo os pares LEGÍTIMOS `(Em Andamento, 0)` e
# `(Em Andamento, 100)`. Não toca no banco: é cálculo puro.
RSpec.describe Tasks::ApplyTransitionService do
  def resolve(current_status:, current_progress:, **input)
    described_class.resolve(current_status: current_status, current_progress: current_progress, **input)
  end

  describe 'entrada por status' do
    it 'status = Concluído → progress 100 e completed' do
      r = resolve(current_status: 'Em Andamento', current_progress: 40, status: 'Concluído')
      expect([r.status, r.progress, r.completed]).to eq(['Concluído', 100, true])
    end

    it 'status = N/A → progress 0' do
      r = resolve(current_status: 'Pendente', current_progress: 30, status: 'N/A')
      expect([r.status, r.progress, r.completed]).to eq(['N/A', 0, false])
    end

    it 'status = Pendente → progress 0' do
      r = resolve(current_status: 'Em Andamento', current_progress: 55, status: 'Pendente')
      expect([r.status, r.progress]).to eq(['Pendente', 0])
    end

    it 'status = Em Andamento → progress INALTERADO' do
      r = resolve(current_status: 'Pendente', current_progress: 35, status: 'Em Andamento')
      expect([r.status, r.progress]).to eq(['Em Andamento', 35])
    end
  end

  describe 'entrada por progress' do
    it 'progress = 100 → Concluído e completed' do
      r = resolve(current_status: 'Em Andamento', current_progress: 90, progress: 100)
      expect([r.status, r.progress, r.completed]).to eq(['Concluído', 100, true])
    end

    it '0 < progress < 100 → Em Andamento' do
      r = resolve(current_status: 'Pendente', current_progress: 0, progress: 45)
      expect([r.status, r.progress]).to eq(['Em Andamento', 45])
    end

    it 'progress = 0 e status ≠ N/A → Pendente' do
      r = resolve(current_status: 'Em Andamento', current_progress: 20, progress: 0)
      expect([r.status, r.progress]).to eq(['Pendente', 0])
    end

    it 'progress = 0 e status = N/A → N/A PRESERVADO (a exceção)' do
      r = resolve(current_status: 'N/A', current_progress: 0, progress: 0)
      expect([r.status, r.progress]).to eq(['N/A', 0])
    end
  end

  describe 'pares legítimos que nenhum teste pode tratar como corrupção (D-CHK)' do
    it '(Em Andamento, 0) é alcançável: status Em Andamento numa tarefa em 0%' do
      r = resolve(current_status: 'Pendente', current_progress: 0, status: 'Em Andamento')
      expect([r.status, r.progress]).to eq(['Em Andamento', 0])
    end

    it '(Em Andamento, 100) é alcançável: reabrir uma tarefa concluída' do
      r = resolve(current_status: 'Concluído', current_progress: 100, status: 'Em Andamento')
      expect([r.status, r.progress]).to eq(['Em Andamento', 100])
    end
  end

  describe 'contrato de entrada' do
    it 'exige EXATAMENTE um de progress XOR status' do
      expect { resolve(current_status: 'Pendente', current_progress: 0) }.to raise_error(ArgumentError)
      expect { resolve(current_status: 'Pendente', current_progress: 0, progress: 10, status: 'N/A') }
        .to raise_error(ArgumentError)
    end
  end
end
