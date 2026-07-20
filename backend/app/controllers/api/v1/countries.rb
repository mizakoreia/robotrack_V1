# frozen_string_literal: true

module Api
  module V1
    class Countries < Grape::API
      format :json

      resource :countries do
        desc 'Lista países com DDI e ISO, com busca parcial'
        params do
          optional :q, type: String
        end
        get do
          data = COUNTRIES
          q = (params[:q] || '').to_s.strip.downcase
          if q.present?
            data = data.select do |c|
              c[:name].downcase.include?(q) || c[:iso2].downcase.include?(q) || c[:dial_code].start_with?(q.gsub('+',
                                                                                                                 ''))
            end
          end
          { countries: data }
        end
      end

      COUNTRIES = [
        { name: 'Brazil', iso2: 'BR', dial_code: '55' },
        { name: 'Argentina', iso2: 'AR', dial_code: '54' },
        { name: 'United States', iso2: 'US', dial_code: '1' },
        { name: 'Canada', iso2: 'CA', dial_code: '1' },
        { name: 'Mexico', iso2: 'MX', dial_code: '52' },
        { name: 'United Kingdom', iso2: 'GB', dial_code: '44' },
        { name: 'Germany', iso2: 'DE', dial_code: '49' },
        { name: 'France', iso2: 'FR', dial_code: '33' },
        { name: 'Spain', iso2: 'ES', dial_code: '34' },
        { name: 'Portugal', iso2: 'PT', dial_code: '351' },
        { name: 'Italy', iso2: 'IT', dial_code: '39' },
        { name: 'Netherlands', iso2: 'NL', dial_code: '31' },
        { name: 'Belgium', iso2: 'BE', dial_code: '32' },
        { name: 'Switzerland', iso2: 'CH', dial_code: '41' },
        { name: 'Austria', iso2: 'AT', dial_code: '43' },
        { name: 'Ireland', iso2: 'IE', dial_code: '353' },
        { name: 'Sweden', iso2: 'SE', dial_code: '46' },
        { name: 'Norway', iso2: 'NO', dial_code: '47' },
        { name: 'Denmark', iso2: 'DK', dial_code: '45' },
        { name: 'Finland', iso2: 'FI', dial_code: '358' },
        { name: 'Poland', iso2: 'PL', dial_code: '48' },
        { name: 'Czech Republic', iso2: 'CZ', dial_code: '420' },
        { name: 'Russia', iso2: 'RU', dial_code: '7' },
        { name: 'China', iso2: 'CN', dial_code: '86' },
        { name: 'Japan', iso2: 'JP', dial_code: '81' },
        { name: 'South Korea', iso2: 'KR', dial_code: '82' },
        { name: 'India', iso2: 'IN', dial_code: '91' },
        { name: 'Australia', iso2: 'AU', dial_code: '61' },
        { name: 'New Zealand', iso2: 'NZ', dial_code: '64' },
        { name: 'South Africa', iso2: 'ZA', dial_code: '27' },
        { name: 'Colombia', iso2: 'CO', dial_code: '57' },
        { name: 'Chile', iso2: 'CL', dial_code: '56' },
        { name: 'Peru', iso2: 'PE', dial_code: '51' },
        { name: 'Paraguay', iso2: 'PY', dial_code: '595' },
        { name: 'Uruguay', iso2: 'UY', dial_code: '598' },
        { name: 'Bolivia', iso2: 'BO', dial_code: '591' },
        { name: 'Ecuador', iso2: 'EC', dial_code: '593' },
        { name: 'Venezuela', iso2: 'VE', dial_code: '58' },
        { name: 'Guatemala', iso2: 'GT', dial_code: '502' },
        { name: 'Honduras', iso2: 'HN', dial_code: '504' },
        { name: 'El Salvador', iso2: 'SV', dial_code: '503' },
        { name: 'Costa Rica', iso2: 'CR', dial_code: '506' },
        { name: 'Panama', iso2: 'PA', dial_code: '507' },
        { name: 'Dominican Republic', iso2: 'DO', dial_code: '1' },
        { name: 'Puerto Rico', iso2: 'PR', dial_code: '1' }
      ].freeze
    end
  end
end
