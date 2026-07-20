# frozen_string_literal: true

# Service responsável por criar/retomar sessão após conclusão de checkout
# Regras de negócio:
# - Se a compra foi concluída e o usuário ainda não está logado no cliente,
#   avaliamos se já existe conta para o e-mail/telefone informado.
#   - Se já existe: não fazemos autologin e retornamos requires_login: true.
#   - Se não existe: criamos/associamos a conta, emitimos JWT e retornamos sessão.
# - Atualizamos/garantimos permissões conforme plano comprado.
module Auth
  class CheckoutSessionService
    include ApiResponseHandler

    # Executa a criação/retomada de sessão pós‑checkout
    # Parâmetros aceitos:
    # - payment_id: ID interno da purchase (PAY_*)
    # - asaas_id: ID do pagamento no Asaas
    # - purchase_identifier: identificador curto da purchase
    def execute!(payment_id: nil, asaas_id: nil, purchase_identifier: nil, subscription_id: nil, subscription_identifier: nil)
      # Tenta localizar compra (one-time) ou assinatura (recorrente)
      purchase = find_purchase(payment_id: payment_id, asaas_id: asaas_id, identifier: purchase_identifier)
      subscription = find_subscription(asaas_id: subscription_id, identifier: subscription_identifier)
      if subscription
        return process_subscription(subscription)
      end

      return not_found_response('Purchase') unless purchase
      # Aceita compras já confirmadas ou PIX aguardando confirmação (será concluída via webhook)
      return validation_error_response('Compra ainda não confirmada') unless purchase.status == 'DONE'

      begin
        purchase.ensure_user_account!
      rescue StandardError => e
        Rails.logger.error("[CheckoutSessionService] ensure_user_account! falhou: #{e.message}")
      end

      user = purchase.user
      return internal_error_response('Usuário não associado à compra') unless user

      # Determina se já existia conta para o e‑mail/telefone informado
      existing_account = account_existed_before_purchase?(purchase: purchase, user: user)

      # Atualiza informações do usuário com dados do checkout (exceto email/whatsapp para contas existentes)
      begin
        update_user_from_purchase(user, purchase, skip_sensitive: existing_account)
      rescue StandardError => e
        Rails.logger.warn("[CheckoutSessionService] update_user_from_purchase falhou: #{e.message}")
      end

      # Sincroniza permissões do usuário de forma defensiva
      begin
        PermissionsSyncService.sync_for_user(user)
      rescue StandardError => e
        Rails.logger.warn("[CheckoutSessionService] sync_for_user falhou: #{e.message}")
      end

      if existing_account
        # Não realizar autologin para contas já existentes
        return success_response({ requires_login: true, user: Api::Entities::User.represent(user) })
      end

      # Emite tokens e retorna sessão
      tokens = Auth::TokenService.new(user).generate_tokens
      payload = {
        user: user,
        access_token: tokens[:token],
        refresh_token: tokens[:refresh_token]
      }
      success_response(Api::Entities::AuthSession.represent(payload))
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    # Localiza a compra por diferentes identificadores
    def find_purchase(payment_id:, asaas_id:, identifier:)
      if payment_id.present?
        Purchase.find_by(payment_id: payment_id)
      elsif asaas_id.present?
        Purchase.find_by(asaas_id: asaas_id)
      elsif identifier.present?
        Purchase.by_any_id(identifier)
      else
        nil
      end
    end

    def find_subscription(asaas_id:, identifier:)
      if asaas_id.present?
        Subscription.find_by(asaas_id: asaas_id)
      elsif identifier.present?
        Subscription.find_by(identifier: identifier)
      else
        nil
      end
    end

    def process_subscription(subscription)
      user = subscription.user
      return not_found_response('User') unless user

      begin
        PermissionsSyncService.sync_for_user(user)
      rescue StandardError => e
        Rails.logger.warn("[CheckoutSessionService] sync_for_user sub falhou: #{e.message}")
      end

      if account_existed_before_subscription?(subscription: subscription, user: user)
        return success_response({ requires_login: true, user: Api::Entities::User.represent(user) })
      end

      tokens = Auth::TokenService.new(user).generate_tokens
      payload = {
        user: user,
        access_token: tokens[:token],
        refresh_token: tokens[:refresh_token]
      }
      success_response(Api::Entities::AuthSession.represent(payload))
    end

    def account_existed_before_subscription?(subscription:, user:)
      # Heurística: considera existente se o usuário foi criado antes da assinatura
      user.created_at <= subscription.created_at - 2.minutes
    end

    # Heurística para saber se a conta já existia antes da compra
    # Ajuste: usa uma janela de segurança de 2 minutos para não classificar
    # como "existente" um usuário criado durante o próprio fluxo de checkout.
    # Assim, contas recém‑criadas recebem autologin.
    def account_existed_before_purchase?(purchase:, user:)
      return false unless user && purchase

      # Se o usuário foi criado próximo/apos a compra, tratamos como novo
      return false if user.created_at >= (purchase.created_at - 2.minutes)

      # Para casos em que o usuário pré‑existente é encontrado por e‑mail/telefone
      buyer_email = purchase.consumer_email&.to_s&.strip&.downcase
      buyer_phone = purchase.consumer_whatsapp&.to_s&.gsub(/\D/, '')

      found_by_email = buyer_email.present? ? User.by_email(buyer_email).first : nil
      found_by_phone = buyer_phone.present? ? User.by_phone(buyer_phone).first : nil

      candidate = found_by_email || found_by_phone || user
      candidate.created_at <= (purchase.created_at - 2.minutes)
    end

    # Atualiza campos do usuário com informações disponíveis do checkout
    # Quando skip_sensitive=true, não altera email/whatsapp
    def update_user_from_purchase(user, purchase, skip_sensitive: false)
      data = extract_buyer_data(purchase)

      # Sempre garantir user_type client
      client_type = UserType.find_by(name: 'client')
      user.user_type_id ||= client_type&.id

      # Nome e documento
      user.name = data[:name] if data[:name].present?
      user.cpf_cnpj = data[:cpf_cnpj] if data[:cpf_cnpj].present?

      # Sensíveis
      unless skip_sensitive
        user.email ||= data[:email] if data[:email].present?
        normalized_phone = data[:whatsapp].to_s.gsub(/\D/, '')
        user.phone ||= normalized_phone if normalized_phone.present?
      end

      # Endereço e cardholder quando disponíveis
      user.cep = data[:cardholder_postal_code] if data[:cardholder_postal_code].present?
      user.number = data[:cardholder_address_number] if data[:cardholder_address_number].present?
      user.cardholder_name = data[:cardholder_name] if data[:cardholder_name].present?
      user.cardholder_email = data[:email] if data[:email].present?
      user.cardholder_cpf_cnpj = data[:cpf_cnpj] if data[:cpf_cnpj].present?

      # Associação de customer_id (Asaas)
      user.customer_id ||= purchase.customer_id if purchase.customer_id.present?

      user.save!
    end

    # Extrai dados do comprador do objeto purchase (payment_data/asaas_data/consumer_*)
    def extract_buyer_data(purchase)
      base = {
        name: purchase.consumer_name,
        email: purchase.consumer_email,
        whatsapp: purchase.consumer_whatsapp,
        cpf_cnpj: purchase.consumer_cpf_cnpj
      }

      pd = purchase.payment_data.is_a?(Hash) ? purchase.payment_data : {}
      buyer = pd['buyer'] || {}
      cardholder = {
        cardholder_name: buyer['cardholder_name'],
        cardholder_postal_code: buyer['cardholder_postal_code'],
        cardholder_address_number: buyer['cardholder_address_number']
      }

      base.merge(cardholder).transform_keys(&:to_sym)
    end
  end
end
