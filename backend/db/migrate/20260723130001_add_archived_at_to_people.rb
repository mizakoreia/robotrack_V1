# frozen_string_literal: true

# workspace-settings G1 (§3.9, D-SENTINEL, D-PERSON-DEL) — o arquivamento de
# `Person`. Remover um chip da Equipe é ARQUIVAR (`archived_at`), nunca `DELETE`:
# `task_advances` (append-only) e `audit_logs` carregam o snapshot do nome e a
# trilha é imutável.
#
# Três invariantes NO BANCO (não só na tela/policy):
#   1. `archived_at` nullable (a pessoa some dos seletores quando preenchido);
#   2. o índice único de nome normalizado vira PARCIAL (`WHERE archived_at IS NULL`)
#      — arquivar "Ana" LIBERA criar uma nova "Ana" ativa; a arquivada não colide;
#   3. `CHECK (btrim(name) <> '')` — chip vazio recusado no banco;
#   4. trigger `BEFORE UPDATE OF archived_at`: arquivar quem tem membership ATIVA é
#      remoção de MEMBRO (workspace-invitations, com revogação em tempo real), não
#      ação desta tela → o banco RECUSA (o `rails console` também bate na parede).
class AddArchivedAtToPeople < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE people ADD COLUMN archived_at timestamptz NULL;
      ALTER TABLE people ADD CONSTRAINT chk_people_name_not_blank CHECK (btrim(name) <> '');

      DROP INDEX index_people_on_workspace_id_and_normalized_name;
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_normalized_name
        ON people (workspace_id, lower(btrim(name))) WHERE archived_at IS NULL;

      CREATE OR REPLACE FUNCTION people_forbid_archive_active_member() RETURNS trigger AS $$
      BEGIN
        IF NEW.archived_at IS NOT NULL AND OLD.archived_at IS NULL
           AND EXISTS (SELECT 1 FROM memberships WHERE person_id = NEW.id) THEN
          RAISE EXCEPTION 'pessoa com membership ativa não pode ser arquivada por esta tela '
            '(workspace-settings D-PERSON-DEL: use a remoção de membro)';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_people_forbid_archive_active_member
        BEFORE UPDATE OF archived_at ON people
        FOR EACH ROW EXECUTE FUNCTION people_forbid_archive_active_member();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS trg_people_forbid_archive_active_member ON people;
      DROP FUNCTION IF EXISTS people_forbid_archive_active_member();
      DROP INDEX index_people_on_workspace_id_and_normalized_name;
      CREATE UNIQUE INDEX index_people_on_workspace_id_and_normalized_name
        ON people (workspace_id, lower(btrim(name)));
      ALTER TABLE people DROP CONSTRAINT chk_people_name_not_blank;
      ALTER TABLE people DROP COLUMN archived_at;
    SQL
  end
end
