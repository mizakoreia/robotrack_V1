# frozen_string_literal: true

require 'rails_helper'

# invite-by-code G1.5 — geração, normalização e hashing do código curto (design
# D2/§"Geração criptográfica"). Puro model: não toca banco, prova as garantias que
# o banco não faz sozinho (alfabeto, entropia, tolerância de leitura).
RSpec.describe 'Invitation short code (geração/normalização)', type: :model do
  describe '.generate_short_code' do
    it 'gera 10.000 códigos distintos, de 8 chars, sem I/L/O/U' do
      codigos = Array.new(10_000) { Invitation.generate_short_code }

      expect(codigos.uniq.size).to eq(10_000)
      expect(codigos).to all(match(/\A[0-9A-HJKMNP-TV-Z]{8}\z/)) # Crockford: sem I, L, O, U
      expect(codigos.join).not_to match(/[ILOU]/)
    end

    it 'só usa símbolos do alfabeto Crockford declarado' do
      alfabeto = Invitation::SHORT_CODE_ALPHABET.chars.to_set
      1_000.times do
        Invitation.generate_short_code.each_char do |c|
          expect(alfabeto).to include(c)
        end
      end
    end
  end

  describe '.normalize_code' do
    it 'sobe para maiúsculas e remove hífen/espaço' do
      expect(Invitation.normalize_code('4k7p-9qmx')).to eq('4K7P9QMX')
      expect(Invitation.normalize_code(' 4k7p 9qmx ')).to eq('4K7P9QMX')
    end

    it 'mapeia os ambíguos de leitura (I/L→1, O→0)' do
      expect(Invitation.normalize_code('IL0O')).to eq('1100') # I→1, L→1, 0→0, O→0
      expect(Invitation.normalize_code('o1i-l0')).to eq('01110') # O→0, 1, I→1, L→1, 0
    end
  end

  describe '.code_hash_for' do
    it 'é determinístico e tolerante: variações da mesma entrada casam o mesmo hash' do
      canonico = Invitation.code_hash_for('4K7P9QMX')

      expect(Invitation.code_hash_for('4k7p-9qmx')).to eq(canonico)
      expect(Invitation.code_hash_for(' 4K7P 9QMX ')).to eq(canonico)
      expect(canonico).to match(/\A[0-9a-f]{64}\z/) # HMAC-SHA256 hex
    end

    it 'entradas diferentes produzem hashes diferentes' do
      expect(Invitation.code_hash_for('4K7P9QMX')).not_to eq(Invitation.code_hash_for('4K7P9QMY'))
    end

    it 'depende do pepper: pepper diferente muda o hash' do
      base = Invitation.code_hash_for('4K7P9QMX')
      allow(Invitation).to receive(:code_pepper).and_return('outro-pepper')
      expect(Invitation.code_hash_for('4K7P9QMX')).not_to eq(base)
    end

    it 'devolve nil para entrada vazia' do
      expect(Invitation.code_hash_for('')).to be_nil
      expect(Invitation.code_hash_for(nil)).to be_nil
    end
  end

  describe 'assign_short_code (callback on: :create)' do
    it 'ao validar um convite novo, atribui hash, expiração de 48h e claro transiente' do
      inv = Invitation.new(email: 'joao@fabrica.com', role: 'view')
      inv.valid? # dispara before_validation on: :create

      expect(inv.short_code).to match(/\A[0-9A-HJKMNP-TV-Z]{8}\z/)
      expect(inv.code_hash).to eq(Invitation.code_hash_for(inv.short_code))
      expect(inv.code_expires_at).to be_within(5.seconds).of(Time.current + 48.hours)
      expect(inv.code_attempts).to eq(0)
    end

    it 'a expiração do código (48h) é mais curta que a do link (7 dias)' do
      inv = Invitation.new(email: 'joao@fabrica.com', role: 'view')
      inv.valid?

      expect(inv.code_expires_at).to be < inv.expires_at
    end

    it 'não regenera se code_hash já foi atribuído' do
      inv = Invitation.new(email: 'joao@fabrica.com', role: 'view', code_hash: 'ja-existe')
      inv.valid?

      expect(inv.code_hash).to eq('ja-existe')
      expect(inv.short_code).to be_nil
    end
  end

  describe '#code_status' do
    it 'nil quando não há código (link puro)' do
      expect(Invitation.new(code_hash: nil).code_status).to be_nil
    end

    it 'active para código presente, não usado, não travado, não expirado' do
      inv = Invitation.new(code_hash: 'h', code_expires_at: 1.hour.from_now)
      expect(inv.code_status).to eq('active')
    end

    it 'used vence tudo' do
      inv = Invitation.new(code_hash: 'h', used_at: Time.current, code_locked_at: Time.current,
                           code_expires_at: 1.hour.ago)
      expect(inv.code_status).to eq('used')
    end

    it 'locked vence expired' do
      inv = Invitation.new(code_hash: 'h', code_locked_at: Time.current, code_expires_at: 1.hour.ago)
      expect(inv.code_status).to eq('locked')
    end

    it 'expired quando passou a janela de 48h' do
      inv = Invitation.new(code_hash: 'h', code_expires_at: 1.minute.ago)
      expect(inv.code_status).to eq('expired')
    end
  end
end
