# frozen_string_literal: true

class CreateUserTypes < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :user_types, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.integer :hierarchy_level, null: false
      t.timestamps
    end

    add_index :user_types, :name, unique: true
    add_index :user_types, :hierarchy_level, unique: true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO user_types (id, name, description, hierarchy_level, created_at, updated_at)
          VALUES#{' '}
            (gen_random_uuid(), 'OG', 'Super Admin - Acesso total ao sistema', 1, NOW(), NOW()),
            (gen_random_uuid(), 'client', 'Cliente - Usuário padrão do sistema', 2, NOW(), NOW());
        SQL
      end

      dir.down do
        execute <<-SQL
          DELETE FROM user_types WHERE name IN ('OG', 'client');
        SQL
      end
    end
  end
end
