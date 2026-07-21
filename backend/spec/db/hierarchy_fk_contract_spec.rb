# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 7.2 (D-H6) — a ARESTA EXPLÍCITA entre esta capacidade
# e as de baixo.
#
# Esta change declara `projects → cells → robots` com ON DELETE CASCADE. As
# tabelas a jusante (`tasks`, `task_advances`, `task_assignees`) são de
# `robot-tasks` e `progress-advances` — e se alguma delas chegar com RESTRICT ou
# SET NULL, excluir um projeto com tarefas passa a responder 500 de violação de
# FK EM PRODUÇÃO. Este spec é o que impede isso: assim que a tabela existir, ele
# cobra o CASCADE.
RSpec.describe 'Contrato de cascade da hierarquia' do
  conn = ActiveRecord::Base.connection

  # filho => pai que precisa cascatear.
  #
  # `task_advances` NÃO está aqui de propósito: `progress-advances` (D-IMUT) a fez
  # `ON DELETE RESTRICT` — a trilha de comissionamento é IMUTÁVEL, e nem um cascade
  # a apaga (o trigger de imutabilidade recusaria o DELETE de qualquer forma). Ver
  # o exemplo dedicado abaixo e a TENSÃO documentada nele.
  CONTRATO = {
    'cells' => 'projects',
    'robots' => 'cells',
    'tasks' => 'robots',
    'task_assignees' => 'tasks'
  }.freeze

  def self.existe?(conn, tabela)
    conn.select_value("SELECT to_regclass(#{conn.quote("public.#{tabela}")})").present?
  end

  CONTRATO.each do |filho, pai|
    if existe?(conn, filho)
      it "#{filho} → #{pai} é ON DELETE CASCADE" do
        fk = conn.select_one(<<~SQL)
          SELECT confdeltype, pg_get_constraintdef(oid) AS def FROM pg_constraint
          WHERE conrelid = '#{filho}'::regclass AND contype = 'f'
            AND confrelid = '#{pai}'::regclass
        SQL

        expect(fk).not_to be_nil, "#{filho} não tem FK para #{pai}"
        expect(fk['confdeltype']).to eq('c'),
                                     "#{filho} → #{pai} veio com confdeltype='#{fk['confdeltype']}' " \
                                     "(a=NO ACTION, r=RESTRICT, n=SET NULL). Sem CASCADE, excluir um projeto " \
                                     "com #{filho} responde 500 de violação de FK em produção (D-H6)."
      end
    else
      it "#{filho} → #{pai} é ON DELETE CASCADE" do
        capacidade = filho == 'tasks' ? 'robot-tasks' : 'progress-advances/robot-tasks'
        pending "bloqueada por #{capacidade} — a tabela #{filho} ainda não existe; " \
                'quando ela chegar, este exemplo passa a cobrar o CASCADE automaticamente'
        raise "implementar quando #{capacidade} criar #{filho}"
      end
    end
  end

  # progress-advances D-IMUT — a EXCEÇÃO ao contrato de cascade: a trilha é
  # imutável e sobrevive à tarefa.
  #
  # TENSÃO CONHECIDA (documentada para o próximo agente / decisão de produto):
  # `tasks → robots` ainda é CASCADE (commissioning-hierarchy), mas `task_advances
  # → tasks` é RESTRICT. Logo, HARD-deletar um robô que tenha tarefas COM avanços
  # falharia (o cascade tentaria apagar `tasks`, e a RESTRICT/trigger de
  # `task_advances` aborta → 500). `progress-advances` mitigou pela metade
  # (soft-delete em `tasks` via `DeleteService`), mas o cascade de HARD delete da
  # hierarquia (excluir robô/célula/projeto) não passa por lá. Resolução completa
  # = soft-delete na hierarquia — FOLLOW-UP de commissioning-hierarchy/robot-tasks,
  # fora do escopo de progress-advances. Hoje a suíte fica verde porque nenhum
  # spec de exclusão da hierarquia cria tarefas com avanços antes de excluir.
  it 'task_advances → tasks é ON DELETE RESTRICT (trilha imutável, D-IMUT)' do
    fk = conn.select_one(<<~SQL)
      SELECT confdeltype FROM pg_constraint
      WHERE conrelid = 'task_advances'::regclass AND contype = 'f'
        AND confrelid = 'tasks'::regclass
    SQL
    expect(fk).not_to be_nil, 'task_advances não tem FK para tasks'
    expect(fk['confdeltype']).to eq('r'),
                                 'task_advances → tasks tem de ser RESTRICT: a trilha de comissionamento ' \
                                 'não é apagada em cascata (D-IMUT). tasks usa soft-delete.'
  end

  it 'audit_logs e notifications NÃO cascateiam da hierarquia (D-H6)' do
    %w[audit_logs notifications].each do |tabela|
      next unless self.class.existe?(conn, tabela)

      fks = conn.select_values(<<~SQL)
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conrelid = '#{tabela}'::regclass AND contype = 'f'
          AND confrelid IN ('projects'::regclass, 'cells'::regclass, 'robots'::regclass)
      SQL

      expect(fks).to be_empty,
                     "#{tabela} tem FK para a hierarquia: o log/notificação de que o robô existiu " \
                     'tem de SOBREVIVER ao robô (D-H6) — o id vai como valor solto, não como referência.'
    end
  end
end
