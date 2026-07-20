# frozen_string_literal: true

require 'rails_helper'

# Guarda de papel de banco — tenant-isolation §"Papel de banco" (tarefa 1.4).
#
# A RLS só protege se a conexão de runtime NÃO puder contorná-la. Um papel
# `SUPERUSER` ou com `BYPASSRLS` ignora toda política, e apontar `DATABASE_URL`
# para o superusuário local é o default de todo setup de desenvolvimento — o
# modo de falha silencioso que desliga o isolamento inteiro e mantém a suíte
# verde. Este spec reprova exatamente esse caso.
RSpec.describe 'Papel de banco da conexão de runtime' do
  def role_flags
    row = ActiveRecord::Base.connection.select_one(<<~SQL)
      SELECT rolsuper, rolbypassrls, current_user AS name
      FROM pg_roles
      WHERE rolname = current_user
    SQL
    {
      name: row['name'],
      super: ActiveModel::Type::Boolean.new.cast(row['rolsuper']),
      bypassrls: ActiveModel::Type::Boolean.new.cast(row['rolbypassrls'])
    }
  end

  it 'não é SUPERUSER' do
    flags = role_flags
    expect(flags[:super]).to be(false),
                             "a conexão de runtime é '#{flags[:name]}', que é SUPERUSER — " \
                             'a RLS está desligada de fato. Aponte DATABASE_URL para robotrack_app.'
  end

  it 'não tem BYPASSRLS' do
    flags = role_flags
    expect(flags[:bypassrls]).to be(false),
                                 "a conexão de runtime é '#{flags[:name]}', que tem BYPASSRLS — " \
                                 'ela ignora toda política de tenant. Aponte DATABASE_URL para robotrack_app.'
  end
end
