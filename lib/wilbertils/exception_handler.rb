require 'active_support/concern'

module Wilbertils
  module ExceptionHandler
    extend ActiveSupport::Concern

    included do
      def rescue_programmatic_error(exception)
        logger.error "ExceptionHandler : #{exception.class }#{exception.inspect}"
        logger.error "#{exception.backtrace.join("\n")}"

        return if ENV['ENVIRONMENT_NAME'] == 'ci' || !ENV['ENVIRONMENT_NAME']

        Airbrake.notify_or_ignore(
          exception,
          :cgi_data => ENV.to_hash
        )
      end
    end


  end
end

