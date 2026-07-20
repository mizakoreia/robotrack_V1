class DashboardKpisBroadcastJob < ApplicationJob
  queue_as :default

  def perform
    kpis = AnalyticsService.new.send(:compute_kpis_realtime)
    DashboardChannel.broadcast_to("dashboard:kpis", { kpis: kpis })
  end
end

