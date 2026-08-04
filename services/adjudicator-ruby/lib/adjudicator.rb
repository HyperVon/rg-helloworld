# frozen_string_literal: true

require_relative 'adjudicator/version'

module Adjudicator
  SERVICE_NAME = 'adjudicator'

  def self.banner
    "#{SERVICE_NAME} #{VERSION} (Milestone 0 skeleton)"
  end
end
