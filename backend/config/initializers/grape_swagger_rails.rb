# frozen_string_literal: true

# config/initializers/grape_swagger_rails.rb
GrapeSwaggerRails.options.url      = '/api/v1/swagger_doc'
GrapeSwaggerRails.options.app_name = 'Polemk API'
GrapeSwaggerRails.options.before_action do
  GrapeSwaggerRails.options.app_url = request.protocol + request.host_with_port
end
GrapeSwaggerRails.options.api_auth = 'bearer'
GrapeSwaggerRails.options.api_key_name = 'Authorization'
GrapeSwaggerRails.options.api_key_type = 'header'
GrapeSwaggerRails.options.doc_expansion = 'full'
GrapeSwaggerRails.options.hide_url_input = false
GrapeSwaggerRails.options.hide_api_key_input = false
