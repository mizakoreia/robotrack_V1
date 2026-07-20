# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth 1.5 — as invariantes de identidade moram no BANCO, não só no
# model. O que se prova aqui é que o Postgres recusa o bypass do model
# (`update_column` pula validações) e que o nome é normalizado na escrita.
RSpec.describe User, type: :model do
  describe 'normalização de nome (D4.6)' do
    it 'remove pontas e colapsa espaços internos na escrita' do
      user = create(:user, :with_password, name: '  Ana   Souza  ')

      expect(user.reload.name).to eq('Ana Souza')
    end

    it 'recusa um nome só de espaços (vira vazio → presença falha)' do
      user = build(:user, :with_password, name: '   ')

      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it 'recusa um nome com menos de 2 caracteres não-brancos' do
      user = build(:user, :with_password, name: 'A')

      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end
  end

  describe 'CHECK de nome mínimo resiste ao bypass do model' do
    it 'levanta StatementInvalid quando update_column grava "A"' do
      user = create(:user, :with_password)

      # A violação aborta a transação do exemplo; não emitimos query depois (um
      # `reload` aqui daria PG::InFailedSqlTransaction). O raise já é a prova.
      expect { user.update_column(:name, 'A') }
        .to raise_error(ActiveRecord::StatementInvalid, /users_name_min_length/)
    end
  end

  describe 'CHECK de credencial resiste ao bypass do model (D4.7)' do
    it 'recusa provider nulo com encrypted_password vazio' do
      # Usuária de senha: provider nulo, encrypted_password presente. Zerar a
      # senha por SQL cru a deixaria sem nenhum caminho de login.
      user = create(:user, :with_password)
      expect(user.provider).to be_nil

      expect { user.update_column(:encrypted_password, '') }
        .to raise_error(ActiveRecord::StatementInvalid, /users_credential_present/)
    end

    it 'aceita provider presente sem senha (conta só-Google)' do
      user = build(:user, :google_only)

      expect(user).to be_valid
      expect(user.save).to be(true)
      expect(user.reload.encrypted_password).to eq('')
      expect(user.provider).to eq('google_oauth2')
    end

    it 'aceita senha presente sem provider (conta local)' do
      user = build(:user, :with_password)

      expect(user).to be_valid
      expect(user.save).to be(true)
      expect(user.reload.encrypted_password).to be_present
      expect(user.provider).to be_nil
    end
  end

  describe 'senha mínima de 6 (§3.1)' do
    it 'recusa senha de 5 caracteres' do
      user = build(:user, password: 'abcde')

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it 'aceita senha de 6 caracteres' do
      user = build(:user, password: 'abcdef')

      expect(user).to be_valid
    end
  end
end
