# frozen_string_literal: true

module Api
  module V1
    class Downloads < Grape::API
      include Api::V1::ControllerHelpers

      resource :downloads do
        desc 'Download do Build da Aplicação' do
          summary 'Download autenticado do arquivo de build'
          security [{ Bearer: [] }]
        end
        get :build do
          authenticate_user!
          
          file_path = Rails.root.join('storage', 'builds', 'app-build.zip')
          
          unless File.exist?(file_path)
            error!({ error: 'Arquivo de build não encontrado' }, 404)
          end
          
          content_type 'application/zip'
          header['Content-Disposition'] = 'attachment; filename="app-build.zip"'
          env['api.format'] = :binary
          
          body File.binread(file_path)
        end
      end
    end
  end
end
