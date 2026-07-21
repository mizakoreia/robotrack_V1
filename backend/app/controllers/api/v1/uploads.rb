# frozen_string_literal: true

module Api
  module V1
    class Uploads < Grape::API
      helpers Api::V1::ControllerHelpers
      helpers do
        def require_user!
          return if defined?(@current_user) && @current_user.present?

          error!({ error: 'unauthorized', message: 'Usuário não autenticado' },
                 401)
        end
      end

      resource :avatar do
        params do
          requires :file, type: File, desc: 'Arquivo de imagem'
        end

        route_setting :policy, access: :authenticated
        post '', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [415, 'Unsupported Media Type'],
          [500, 'Internal Server Error']
        ] do
          require_user!
          f = params[:file]
          ct = (f[:type] || '').to_s
          unless ct.start_with?('image/')
            error!({ error: 'unsupported_media_type', message: 'Arquivo deve ser imagem' },
                   415)
          end

          ext = File.extname((f[:filename] || '').to_s).downcase
          ext = '.jpg' if ext.blank?
          dir = Rails.root.join('public', 'uploads', 'avatars')
          FileUtils.mkdir_p(dir)
          name = "#{SecureRandom.uuid}#{ext}"
          path = dir.join(name)
          IO.copy_stream(f[:tempfile], path)
          status 201
          { url: "#{request.base_url}/uploads/avatars/#{name}" }
        rescue StandardError => e
          error!({ error: 'internal_error', message: e.message }, 500)
        end
      end
    end
  end
end
