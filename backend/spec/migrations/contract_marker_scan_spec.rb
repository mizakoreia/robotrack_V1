# frozen_string_literal: true

require 'rails_helper'

# delivery-and-observability 8.2 — o scan de migration expand/contract.
RSpec.describe Ops::ContractMigrationGuard do
  let(:migrate_dir) { Rails.root.join('db/migrate').to_s }

  it 'nenhuma migration POSTERIOR ao corte tem operação destrutiva sem marcador' do
    offenders = described_class.offenders(migrate_dir)
    expect(offenders).to be_empty,
                         "migrations destrutivas sem `# contract-of:`: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  describe '.offenders (comportamento)' do
    it 'reprova destrutiva sem marcador acima do corte' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, '20990101000000_drop_it.rb')
        File.write(file, "class DropIt < ActiveRecord::Migration[7.1]\n  def change\n    drop_table :x\n  end\nend\n")
        expect(described_class.offenders(dir)).to include(file)
      end
    end

    it 'aceita destrutiva COM marcador' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, '20990101000000_drop_it.rb')
        File.write(file, "# contract-of: v42\nclass DropIt < ActiveRecord::Migration[7.1]\n  def change\n    drop_table :x\n  end\nend\n")
        expect(described_class.offenders(dir)).to be_empty
        expect(described_class.contract?(file)).to be(true)
      end
    end

    it 'grandfathera destrutiva ABAIXO do corte, mesmo sem marcador' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, '20200101000000_legacy.rb')
        File.write(file, "class Legacy < ActiveRecord::Migration[7.1]\n  def change\n    remove_column :x, :y\n  end\nend\n")
        expect(described_class.offenders(dir)).to be_empty
      end
    end
  end
end
