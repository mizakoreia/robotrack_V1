# frozen_string_literal: true

module Auth
  # Cadastro por e-mail e senha (identity-and-auth 4.1 / spec §"Cadastro por
  # e-mail e senha"). Cria um `User` local (sem provider), emite o JWT já no
  # cadastro e devolve o resultado no mesmo contrato do SessionService.
  #
  # 409 para e-mail já cadastrado, com corpo que NÃO revela se a conta existente é
  # local ou Google (não vazar por que o e-mail está tomado). 422 para senha
  # curta / nome ausente, mapeado por campo.
  class RegistrationService
    def self.call(name:, email:, password:, remember_me: false)
      normalized = email.to_s.downcase.strip

      if User.exists?(email: normalized)
        return { ok: false, status: 409, error: 'E-mail já cadastrado.' }
      end

      user = User.new(name: name, email: normalized, password: password)

      if user.save
        # workspace-core §5.1/5.2 (D-10) — bootstrap do workspace no cadastro (o
        # cadastro já auto-loga). Cria o workspace + semeia as 31 tarefas-base na
        # mesma transação; idempotente. Sem isto, o novo usuário entra sem workspace
        # e a Visão Geral falha para sempre (BUG 6).
        ::Workspaces::BootstrapService.new(user: user).call
        token, = TokenService.issue(user, remember_me: remember_me)
        { ok: true, status: 201, token: token, user: user }
      elsif user.errors.key?(:email) && user.errors.details[:email].any? { |e| e[:error] == :taken }
        # Corrida: outra requisição criou o mesmo e-mail entre o exists? e o save.
        { ok: false, status: 409, error: 'E-mail já cadastrado.' }
      else
        { ok: false, status: 422, errors: user.errors.messages }
      end
    end
  end
end
