# frozen_string_literal: true

module Api
  module V1
    class Users < Grape::API
      helpers Api::V1::ControllerHelpers

      helpers do
        def require_og!
          return if defined?(@current_user) && @current_user.present? && @current_user.og?

          error!({ error: 'forbidden', message: 'Somente usuários OG' },
                 403)
        end
      end

      # ===============================================
      # USERS - VERIFICAÇÃO POR WHATSAPP
      # ===============================================

      # GET /api/v1/users/find_by_whatsapp - Buscar usuário por WhatsApp
      resource :find_by_whatsapp do
        desc 'Buscar usuário por número de WhatsApp' do
          summary 'Buscar usuário por número de WhatsApp'
          detail 'Verifica se existe um usuário cadastrado com o número de WhatsApp fornecido. Se existir, retorna os dados do usuário. Caso contrário, retorna a URL de login.'
          success [code: 200, message: 'Ok']
          named 'Find User by WhatsApp Response'
        end

        params do
          requires :whatsapp, type: String, desc: 'Número de WhatsApp do usuário (ex: 5548999999999)'
        end

        get '', http_codes: [
          [404, 'Usuário não encontrado - retorna URL de login'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [500, 'Internal Server Error']
        ] do
          process_service_response(UsersService.find_by_whatsapp(params))
        end
      end

      # ===============================================
      # USERS - LISTAGEM, CRIAÇÃO, VISUALIZAÇÃO, REMOÇÃO (Somente OG)
      # ===============================================
      resource '' do
        desc 'Listar usuários (Somente OG)' do
          summary 'Listar usuários'
          detail 'Retorna usuários com paginação, busca e filtro por tipo.'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          optional :q, type: String, desc: 'Busca por nome, email ou telefone'
          optional :type, type: String, desc: 'Filtro por tipo de usuário (og, client)'
          optional :page, type: Integer, default: 1, desc: 'Página'
          optional :per_page, type: Integer, default: 20, desc: 'Itens por página'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [500, 'Internal Server Error']
        ] do
          require_og!
          result = UsersService.index(params)
          set_pagination_headers(result[:data][:total], params[:page] || 1, params[:per_page] || 20)
          process_service_response(result)
        end

        desc 'Criar usuário (Somente OG)' do
          summary 'Criar usuário'
          detail 'Cria um novo usuário. Email ou telefone devem ser informados.'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          optional :email, type: String, desc: 'Email do usuário'
          optional :phone, type: String, desc: 'Telefone (WhatsApp)'
          optional :name, type: String, desc: 'Nome'
          optional :avatar_url, type: String, desc: 'URL do avatar'
          optional :cpf_cnpj, type: String, desc: 'CPF/CNPJ'
          optional :cep, type: String, desc: 'CEP'
          optional :street, type: String, desc: 'Rua'
          optional :number, type: String, desc: 'Número'
          optional :complement, type: String, desc: 'Complemento'
          optional :district, type: String, desc: 'Bairro'
          optional :city, type: String, desc: 'Cidade'
          optional :state, type: String, desc: 'Estado (UF)'
          optional :user_type_id, type: Integer, desc: 'Tipo de usuário (UserType)'
        end

        post '', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          require_og!
          process_service_response(UsersService.create(params))
        end
      end

      route_param :id do
        desc 'Buscar usuário por ID (Somente OG)' do
          summary 'Detalhe do usuário'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [404, 'Not Found']
        ] do
          require_og!
          process_service_response(UsersService.show(params))
        end

        desc 'Excluir usuário (Somente OG)' do
          summary 'Excluir usuário'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        delete '', http_codes: [
          [204, 'No Content'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [404, 'Not Found']
        ] do
          require_og!
          process_service_response(UsersService.destroy(params))
        end

        # ===============================================
        # USERS - ATUALIZAÇÃO (Somente OG)
        # ===============================================
        desc 'Atualizar usuário (Somente OG)' do
          summary 'Atualizar usuário'
          detail 'Atualiza um usuário existente pelo ID.'
          success [code: 200, message: 'Ok', model: Api::Entities::User]
        end

        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
          optional :email, type: String, desc: 'Email do usuário'
          optional :phone, type: String, desc: 'Telefone (WhatsApp)'
          optional :name, type: String, desc: 'Nome'
          optional :avatar_url, type: String, desc: 'URL do avatar'
          optional :cpf_cnpj, type: String, desc: 'CPF/CNPJ'
          optional :cep, type: String, desc: 'CEP'
          optional :street, type: String, desc: 'Rua'
          optional :number, type: String, desc: 'Número'
          optional :complement, type: String, desc: 'Complemento'
          optional :district, type: String, desc: 'Bairro'
          optional :city, type: String, desc: 'Cidade'
          optional :state, type: String, desc: 'Estado (UF)'
          optional :user_type_id, type: Integer, desc: 'Tipo de usuário (UserType)'
          optional :biography, type: String, desc: 'Biografia (ActionText)'
        end

        put '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          require_og!
          process_service_response(UsersService.update(params))
        end

        patch '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          require_og!
          process_service_response(UsersService.update(params))
        end
      end

      # ===============================================
      # USERS - ESTATÍSTICAS (Somente OG)
      # ===============================================
      resource :stats do
        desc 'Estatísticas de usuários (Somente OG)'
        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden']
        ] do
          require_og!
          process_service_response(UsersService.stats(params))
        end
      end
    end
  end
end
