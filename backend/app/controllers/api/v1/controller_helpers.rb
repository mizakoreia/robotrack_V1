# frozen_string_literal: true

module Api
  module V1
    module ControllerHelpers
      def process_service_response(response)
        status response[:status]

        if (200..299).include?(response[:status])
          response[:data]
        else
          error_payload = { error: response[:error] || response[:message] }
          error_payload[:details] = response[:details] if response[:details]
          error!(error_payload, response[:status])
        end
      end

      def set_pagination_headers(total, page, per_page)
        header 'X-Total-Count', total
        header 'X-Page', page
        header 'X-Per-Page', per_page
      end
    end
  end
end
