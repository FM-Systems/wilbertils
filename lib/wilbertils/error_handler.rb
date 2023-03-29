require 'active_support/concern'
require 'active_support/rescuable'

module Wilbertils
  module ErrorHandler
    extend ActiveSupport::Concern
    include ActiveSupport::Rescuable

    included do
      rescue_from(StandardError)                               { |e| rescue_error(e, error_code: :unhandled,      status: :internal_server_error) }
      rescue_from(ActionController::InvalidAuthenticityToken)  { |e| rescue_error(e, error_code: :unauthorized,   status: :unauthorized) }
      rescue_from(ActiveRecord::StaleObjectError)              { |e| rescue_error(e, error_code: :stale,          status: :internal_server_error) }
      rescue_from(ActiveRecord::RecordNotFound)                { |e| rescue_error(e, error_code: :missing_record, status: :not_found) }
    end

    def rescue_error(error, **options)
      Wilbertils::ErrorHandler.rescue_error(error, **options)
      render_error(error, options[:error_code], options[:status]) unless options[:render_error] == false
    end

    def render_error error, code, status
      return unless defined?(render)
      render json: { errors: [ { message: error.message, error_code: code || :unhandled } ] },
        status: status || :internal_server_error
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

