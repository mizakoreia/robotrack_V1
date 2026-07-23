# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 8.3 — o backup verificado que precede a migration destrutiva.
RSpec.describe Ops::VerifiedBackup do
  let(:now) { Time.utc(2026, 7, 23, 12, 0, 0) }
  let(:counts) { { 'workspaces' => 3, 'projects' => 10, 'audit_logs' => 500 } }

  def backup(over = {})
    {
      taken_at: now - 600, # 10 min atrás
      restore_verified: true,
      source_counts: counts,
      restored_counts: counts
    }.merge(over)
  end

  it 'rpo_seconds mede a distância do backup a agora' do
    expect(described_class.rpo_seconds(now - 600, now)).to eq(600)
  end

  it 'stale? true acima de 1h' do
    expect(described_class.stale?(now - 3_601, now)).to be(true)
    expect(described_class.stale?(now - 600, now)).to be(false)
    expect(described_class.stale?(nil, now)).to be(true)
  end

  it 'counts_match? compara as tabelas-âncora' do
    expect(described_class.counts_match?(counts, counts)).to be(true)
    expect(described_class.counts_match?(counts, counts.merge('projects' => 9))).to be(false)
  end

  describe '.assert_safe_for_contract!' do
    it 'passa com backup fresco, restaurado e batendo' do
      expect(described_class.assert_safe_for_contract!(backup: backup, now: now)).to be(true)
    end

    it 'aborta com backup velho (> 1h)' do
      expect { described_class.assert_safe_for_contract!(backup: backup(taken_at: now - 7_200), now: now) }
        .to raise_error(/mais de 1h/)
    end

    it 'aborta quando o restore não foi verificado' do
      expect { described_class.assert_safe_for_contract!(backup: backup(restore_verified: false), now: now) }
        .to raise_error(/não passou no restore/)
    end

    it 'aborta quando as contagens divergem' do
      expect do
        described_class.assert_safe_for_contract!(backup: backup(restored_counts: counts.merge('audit_logs' => 499)), now: now)
      end.to raise_error(/contagens divergem/)
    end

    it 'aborta sem backup' do
      expect { described_class.assert_safe_for_contract!(backup: nil, now: now) }.to raise_error(/backup ausente/)
    end
  end
end
