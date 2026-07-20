# frozen_string_literal: true

class PermissionsChannel < ApplicationCable::Channel
  def subscribed
    user_id = params[:user_id]
    reject unless user_id.present?
    stream_for("permissions:#{user_id}")
  end
end
