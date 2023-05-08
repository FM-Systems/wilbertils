require 'active_support/concern'
require 'active_support/rescuable'

# Used to raise errors without sending Airbrake or New Relic notifications.
class SilentError < StandardError; end

module Wilbertils
  module ErrorHandler
    extend ActiveSupport::Concern
    include ActiveSupport::Rescuable

    included do
      rescue_from(StandardError)                               { |e| rescue_error(e, error_code: :unhandled,    status: :internal_server_error) }
      rescue_from(SilentError)                                 { |e| rescue_error(e, error_code: :silenced,     status: :bad_request) }

      # Wilbertils is used in non rails applications so check that rails is present for rails specific errors.
      if defined?(ActionController)
        rescue_from(ActionController::InvalidAuthenticityToken)  { |e| rescue_error(e, error_code: :unauthorized, status: :unauthorized) }
      end

      if defined?(ActiveRecord)
        rescue_from(ActiveRecord::StaleObjectError)              { |e| rescue_error(e, error_code: :stale,          status: :internal_server_error) }
        rescue_from(ActiveRecord::RecordNotFound)                { |e| rescue_error(e, error_code: :missing_record, status: :not_found) }
        rescue_from(ActiveRecord::RecordInvalid)                 { |e| rescue_invalid_record(e) }
      end
    end

    def rescue_error(error, **options)
      Wilbertils::ErrorHandler.rescue_error(error, **options)
      render_error(error, options[:error_code], options[:status]) unless options[:render_error] == false
    end

    def rescue_invalid_record error, **options
      rescue_error(error, **options.merge(render_error: false))
      return unless defined?(render)
      render json: { errors: error.record.errors }, status: options[:status] || :bad_request
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

      NewRelic::Agent.notice_error(error, options) unless options[:error_code] == :silenced || error.is_a?(SilentError)
      Airbrake.notify(error, options) unless options[:error_code] == :silenced || error.is_a?(SilentError)
    end

  end
end

