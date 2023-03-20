require 'active_support/concern'
require 'active_support/rescuable'

module Wilbertils
  module ErrorHandler
    extend ActiveSupport::Concern
    include ActiveSupport::Rescuable

    included do
      rescue_from StandardError, :with => :rescue_error
    end

    def rescue_error(error, **options)
      self.class.rescue_error(error, **options)
    end

    def self.rescue_error(error, **options)
      log = defined?(logger) ? logger : Rails.logger

      log.error options[:detailed_message] if options[:detailed_message].present?
      log.error "ErrorHandler: #{error.class} #{error.message}"
      log.error error.backtrace.join("\n")

      NewRelic::Agent.notice_error(error, options)
      Airbrake.notify(error, options)
    end

  end
end

