module Api
  module Entities
    module Analytics
      class Dashboard < Grape::Entity
        expose :sales_monthly
        expose :subscriptions_growth
        expose :leads_distribution
        expose :top_products
        expose :lead_conversion_by_channel
        expose :metrics_summary
        expose :kpis_realtime
        expose :sales_breakdown
        expose :leads_summary
      end
    end
  end
end
