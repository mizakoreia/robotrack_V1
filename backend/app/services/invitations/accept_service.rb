# frozen_string_literal: true

module Invitations
  # workspace-invitations §"Consumo atômico do convite" (tarefas 3.1/3.2 —
  # invariante 6, a mais delicada da change).
  #
  # No legado isto NÃO era atômico: marcar o convite como usado e criar a
  # membership eram duas escritas em coleções distintas, avaliadas
  # independentemente pelas `firestore.rules`. Dois clientes com o mesmo link
  # podiam ambos passar no `create` da membership antes de qualquer `update` do
  # convite. A invariante 6 era uma INTENÇÃO. Aqui ela é garantida.
  #
  # Estrutura, e por que ela é assim:
  #
  # 1. O token é resolvido pela função `invitation_by_token` — o único caminho
  #    que lê o convite sem workspace corrente (o convidado ainda não é membro de
  #    nada). Ela devolve NO MÁXIMO uma linha, por token exato.
  # 2. Só então abre-se a transação NO CONTEXTO DO WORKSPACE DO CONVITE, e a
  #    linha é RELIDA com `FOR UPDATE`. As seis validações rodam sobre a linha
  #    travada, nunca sobre a leitura da etapa 1 — senão o TOCTOU voltaria pela
  #    janela.
  # 3. Toda rejeição é uma EXCEÇÃO (`Rejected`), não um `return`: a partir do
  #    Rails 7 um `return` de dentro do bloco de transação faz COMMIT. Levantar
  #    garante o rollback completo exigido pelo cenário "falha parcial".
  class AcceptService
    include ApiResponseHandler

    # Teto explícito da transação (design §Riscos): o `FOR UPDATE` é curto e toca
    # três tabelas; se algo o segurar além disso, é melhor falhar do que manter a
    # linha do convite travada.
    STATEMENT_TIMEOUT = ENV.fetch('INVITATION_ACCEPT_STATEMENT_TIMEOUT', '5s')

    Rejected = Class.new(StandardError) do
      attr_reader :code, :http_status

      def initialize(code, http_status)
        @code = code
        @http_status = http_status
        super(code)
      end
    end

    def initialize(current_user:, token:, requested_workspace_id: nil, extra_params: {})
      @current_user = current_user
      @token = token.to_s
      @requested_workspace_id = requested_workspace_id.presence
      @extra_params = extra_params
    end

    def call
      reject_unexpected_parameters!

      row = lookup_by_token
      raise Rejected.new('invitation_not_found', 404) if row.nil?

      membership = consume(row['workspace_id'], row['id'])
      success_response({ workspace_id: membership.workspace_id, role: membership.role }, 200)
    rescue Rejected => e
      error_response(e.code, e.http_status)
    rescue ActiveRecord::RecordNotUnique
      # Rede de segurança da segunda camada (índice único parcial em
      # memberships.invitation_id): se por qualquer via duas transações
      # produzissem membership do mesmo convite, uma colide aqui. Traduzida para
      # o MESMO erro de negócio — nunca um 500.
      error_response('invitation_already_used', 409)
    end

    private

    # Condição 6 de D-INV-3, tratada de forma ESTRUTURAL: o papel da membership é
    # lido do convite, nunca do cliente. Mesmo assim mandar `role` no corpo é
    # rejeitado em vez de ignorado — ignorar deixaria um atacante crendo que teve
    # sucesso e esconderia a tentativa.
    def reject_unexpected_parameters!
      extras = @extra_params.keys.map(&:to_s) - %w[token route_info version format]
      raise Rejected.new('unexpected_parameter', 422) if extras.any?
    end

    # Leitura sem workspace corrente, pela função SECURITY DEFINER (D-INV-4).
    def lookup_by_token
      return nil if @token.blank?

      conn = ActiveRecord::Base.connection
      conn.select_one("SELECT id, workspace_id FROM invitation_by_token(#{conn.quote(@token)})")
    end

    def consume(workspace_id, invitation_id)
      Tenant.with(workspace_id: workspace_id, user_id: @current_user.id) do
        ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'")

        invitation = Invitation.lock('FOR UPDATE').find_by(id: invitation_id)
        validate!(invitation, workspace_id)

        person = resolve_person(invitation)
        membership = Membership.create!(
          workspace_id: invitation.workspace_id,
          user: @current_user,
          person: person,
          role: invitation.role,
          invitation: invitation
        )
        invitation.update!(used_at: Time.current, used_by_user_id: @current_user.id)
        membership
      end
    end

    # As SEIS condições da invariante 6, na ordem de D-INV-3, cada uma com o seu
    # código — nunca um 422 genérico que impeça o cliente de distinguir
    # "expirado" de "e-mail errado".
    def validate!(invitation, workspace_id)
      raise Rejected.new('invitation_not_found', 404) if invitation.nil?                        # 1
      raise Rejected.new('invitation_already_used', 409) if invitation.used?                    # 2
      raise Rejected.new('invitation_expired', 410) if invitation.expired?                      # 3
      raise Rejected.new('invitation_workspace_mismatch', 422) unless workspace_matches?(invitation, workspace_id) # 4
      raise Rejected.new('invitation_email_mismatch', 403) unless email_matches?(invitation)    # 5
      raise Rejected.new('already_member', 409) if already_member?(invitation)
    end

    # Condição 4: o workspace do convite tem de ser o alvo. O cliente não escolhe
    # o alvo (ele vem do convite), mas se DECLARAR um (`X-Workspace-Id`) que
    # diverge, isso é erro explícito — não silêncio.
    def workspace_matches?(invitation, workspace_id)
      return false unless invitation.workspace_id == workspace_id

      @requested_workspace_id.nil? || @requested_workspace_id == invitation.workspace_id
    end

    # Condição 5: comparação com o e-mail AUTENTICADO, nunca com nada vindo do
    # payload. Literal, sem tratar aliases (`a+x@dom` NÃO casa `a@dom`): casar
    # aliases criaria um caminho de escalonamento, já que quem controla um não
    # necessariamente controla o outro.
    def email_matches?(invitation)
      invitation.email.present? && invitation.email == @current_user.email.to_s.strip.downcase
    end

    # Pergunta em aberto (2) do design, decidida: quem já é membro recebe 409 e o
    # convite NÃO é consumido — fica pendente e revogável, para o dono ver que
    # convidou alguém que já estava dentro. O dono do workspace conta como membro
    # (o papel dele é derivado de `owner_user_id`, não de uma linha).
    def already_member?(invitation)
      return true if Workspace.where(id: invitation.workspace_id, owner_user_id: @current_user.id).exists?

      Membership.where(workspace_id: invitation.workspace_id, user_id: @current_user.id).exists?
    end

    # D-INV-5: casa por E-MAIL com a `Person` que ainda não tem conta, ou cria uma
    # nova. Preservar a existente é o ponto — o dono cadastra "João Silva,
    # joao@fabrica.com" como responsável, atribui tarefas e só depois convida;
    # criar uma segunda `Person` partiria o histórico e esvaziaria "Minhas
    # Tarefas".
    def resolve_person(invitation)
      person = Person.find_by(email: invitation.email)

      if person.nil?
        return Person.create!(name: available_name, email: invitation.email, user_id: @current_user.id)
      end

      if person.user_id.present? && person.user_id != @current_user.id
        raise Rejected.new('person_email_conflict', 409)
      end

      person.update!(user_id: @current_user.id) if person.user_id.nil?
      person
    end

    # O casamento é por e-mail, NUNCA por nome. Mas `people` tem índice único de
    # nome normalizado por workspace (Onda 1), então uma `Person` nova homônima de
    # outra colidiria. Desambiguamos o NOME — o vínculo continua sendo o e-mail.
    def available_name
      base = @current_user.display_name.presence || @current_user.email.to_s.split('@').first.presence || 'convidado'
      return base unless name_taken?(base)

      with_email = "#{base} (#{@current_user.email})"
      return with_email unless name_taken?(with_email)

      2.step do |i|
        candidate = "#{base} (#{i})"
        return candidate unless name_taken?(candidate)
      end
    end

    def name_taken?(name)
      Person.where('lower(btrim(name)) = lower(btrim(?))', name).exists?
    end
  end
end
