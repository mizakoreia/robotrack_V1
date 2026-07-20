# frozen_string_literal: true

class DocsController < ActionController::Base
  before_action { ActionView::LookupContext::DetailsKey.clear }

  layout false

  def elements; end
end
