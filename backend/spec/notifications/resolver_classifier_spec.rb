# frozen_string_literal: true

require 'rails_helper'

# in-app-notifications 3.3 — os cinco casos-limite do resolver + classifier.
RSpec.describe 'Notifications resolver e classifier' do
  describe Notifications::RecipientResolver do
    it 'assign: só o delta (novos − anteriores)' do
      r = described_class.resolve(type: :assign, actor_person_id: 'z',
                                  current_assignees: %w[ana bruno diego], previous_assignees: %w[ana bruno])
      expect(r).to eq(%w[diego])
    end

    it 'progress/done: todos os responsáveis MENOS o autor' do
      r = described_class.resolve(type: :progress, actor_person_id: 'bruno',
                                  current_assignees: %w[ana bruno diego])
      expect(r).to contain_exactly('ana', 'diego')
    end

    it 'autor único responsável → conjunto vazio (não erro)' do
      r = described_class.resolve(type: :done, actor_person_id: 'ana', current_assignees: %w[ana])
      expect(r).to eq([])
    end

    it 'autoatribuição (§2.3): o próprio autoatribuído não recebe assign' do
      r = described_class.resolve(type: :assign, actor_person_id: 'ana',
                                  current_assignees: %w[ana], previous_assignees: [])
      expect(r).to eq([])
    end

    it 'pessoa repetida no conjunto bruto é deduplicada' do
      r = described_class.resolve(type: :progress, actor_person_id: 'z',
                                  current_assignees: %w[ana ana bruno])
      expect(r).to contain_exactly('ana', 'bruno')
    end
  end

  describe Notifications::EventClassifier do
    it '0 < to < 100 → :progress' do
      expect(described_class.classify(from: 10, to: 45)).to eq(:progress)
    end

    it 'to == 100 → :done (não :progress)' do
      expect(described_class.classify(from: 60, to: 100)).to eq(:done)
    end

    it 'to == 0 (reset) → nil' do
      expect(described_class.classify(from: 45, to: 0)).to be_nil
    end
  end
end
