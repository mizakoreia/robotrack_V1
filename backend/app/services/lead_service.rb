# frozen_string_literal: true

class LeadService
  class << self
    include ApiResponseHandler

    def list(params)
      offset = params[:o] || 0
      limit = params[:l] || 100
      query = params[:q] || ''

      leads = Lead.offset(offset).limit(limit).order(last_interaction_at: :desc)
      if query.present?
        like = "%#{query}%"
        leads = leads.where(
          'name ILIKE :q OR company_name ILIKE :q OR source_id ILIKE :q OR smart_id ILIKE :q OR session_uuid ILIKE :q',
          q: like
        )
      end

      success_response(Api::Entities::Lead.represent(leads).as_json, 200)
    end

    def get_lead(id)
      lead = Lead.by_any_id(id)
      return not_found_response('Lead') unless lead

      success_response(Api::Entities::Lead.represent(lead).as_json, 200)
    end

    def create(params)
      # Sistema de Match Cross-Channel CORRIGIDO - busca apenas por source_type + source_id

      lead = LeadCrossChannelService.find_or_create_lead(params)

      # Determina código de resposta baseado se foi match exato ou criação nova
      # Note: cross-channel unification só acontece em atualizações posteriores
      status_code = lead.id_previously_changed? ? 201 : 200

      success_response(Api::Entities::Lead.represent(lead).as_json, status_code)
    rescue ActiveRecord::RecordInvalid => e
      validation_error_response(e.message)
    end

    def update(params)
      lead_id = params.delete(:id)
      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      begin
        update_params = params.compact

        # VERIFICA UNIFICAÇÃO CROSS-CHANNEL durante atualização
        # Se a atualização trouxe phone ou ig_username, pode rolar unificação
        if should_check_unification?(update_params)
          Rails.logger.info "🔄 Verificando unificação para lead #{lead.smart_id} com dados: #{update_params.slice(
            :phone, :ig_username
          )}"

          # Monta atributos completos para verificação (dados atuais + novos)
          full_attributes = update_params.with_indifferent_access

          # CORRIGIDO: O service já aplica todos os dados da atualização durante a unificação
          updated_lead = LeadCrossChannelService.check_unification_on_update(lead, full_attributes)

          # IMPORTANTE: Se houve unificação, aplicar campos restantes que não são de unificação
          if updated_lead.id != lead.id || updated_lead.unified_from_channels?
            Rails.logger.info '✅ Unificação realizada. Aplicando campos restantes...'
            remaining_updates = update_params.except(:phone, :ig_username)
            updated_lead.update!(remaining_updates) if remaining_updates.any?
          else
            Rails.logger.info 'ℹ️ Nenhuma unificação necessária. Aplicando atualização normal...'
            # Se não houve unificação, aplica todos os dados normalmente
            updated_lead.update!(update_params)
          end

          lead = updated_lead
        else
          # Atualização normal sem verificação de unificação
          Rails.logger.info "📝 Atualização normal para lead #{lead.smart_id}"
          lead.update!(update_params)
        end

        success_response(Api::Entities::Lead.represent(lead).as_json, 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      rescue ActiveRecord::RecordNotFound
        not_found_response('Lead')
      end
    end

    def destroy(id)
      lead = Lead.by_any_id(id)
      return not_found_response('Lead') unless lead

      begin
        lead.destroy!
        no_content_response
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def add_desire(params)
      lead_id = params[:id]
      desire_text = params[:desire].to_s.strip
      return validation_error_response('O texto do desire não pode estar vazio') if desire_text.blank?

      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      lead.desires ||= []
      lead.desires << desire_text

      begin
        lead.save!
        success_response(Api::Entities::Lead.represent(lead).as_json, 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      end
    end

    def remove_desire(params)
      lead_id = params[:id]
      index = params[:index].to_i

      lead = Lead.by_any_id(lead_id)
      return not_found_response('Lead') unless lead

      desires = lead.desires || []
      return validation_error_response('Índice inválido') if index.negative? || index >= desires.length

      desires.delete_at(index)
      lead.desires = desires

      begin
        lead.save!
        success_response(Api::Entities::Lead.represent(lead).as_json, 200)
      rescue ActiveRecord::RecordInvalid => e
        validation_error_response(e.message)
      end
    end

    private

    # Verifica se a atualização contém campos que podem causar unificação cross-channel
    def should_check_unification?(update_params)
      unification_fields = %i[phone ig_username]
      unification_fields.any? { |field| update_params.key?(field) && update_params[field].present? }
    end
  end
end
