# frozen_string_literal: true

class AddProfileFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :cpf_cnpj, :string
    add_column :users, :cep, :string
    add_column :users, :street, :string
    add_column :users, :number, :string
    add_column :users, :complement, :string
    add_column :users, :district, :string
    add_column :users, :city, :string
    add_column :users, :state, :string
  end
end
