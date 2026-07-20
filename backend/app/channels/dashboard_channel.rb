class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_for("dashboard:kpis")
  end

  def unsubscribed
  end
end

