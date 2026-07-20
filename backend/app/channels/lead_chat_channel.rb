# frozen_string_literal: true

class LeadChatChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.og?

    lead_any_id = params[:lead_id]
    lead = Lead.by_any_id(lead_any_id)
    return reject unless lead

    stream_from "lead_chat_#{lead.id}"
  end

  def unsubscribed; end
end
